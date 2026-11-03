#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=0
PRUNE=1

while [[ "$#" -gt 0 ]]; do
  case $1 in
    --dry-run) DRY_RUN=1; shift ;;
    --no-prune) PRUNE=0; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

: "${PORKBUN_API_KEY:?must be set}"
: "${PORKBUN_SECRET_KEY:?must be set}"
: "${NIX_BIN:=nix}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

PII=$($NIX_BIN eval -f secrets/pii.nix --json)
SVCS=$($NIX_BIN eval --json --impure --expr 'let flake = builtins.getFlake (toString ./.); in (flake.inputs.nixpkgs.lib.evalModules { modules = [ ./modules/services-schema.nix ]; }).config.myServices')
DATA=$(jq -n --argjson pii "$PII" --argjson svcs "$SVCS" -f tools/dns-data.jq)

DOMAIN=$(echo "$DATA" | jq -r '.domain')
DDNS_SUB=$(echo "$DATA" | jq -r '.ddnsSubdomain')

echo "Fetching current Porkbun records for $DOMAIN..."
CURRENT=$(curl -sf -X POST "https://api.porkbun.com/api/json/v3/dns/retrieve/$DOMAIN" \
  -H 'Content-Type: application/json' \
  -d "{\"apikey\":\"$PORKBUN_API_KEY\",\"secretapikey\":\"$PORKBUN_SECRET_KEY\"}")

RECORD_COUNT=$(echo "$CURRENT" | jq '.records | length' 2>/dev/null || echo 0)
echo "Found $RECORD_COUNT current records in Porkbun."

sync_record() {
  local sub="$1" type="$2" content="$3" ttl="${4:-600}"
  local fqdn="$sub.$DOMAIN"
  echo "  Syncing $type $fqdn -> $content"

  local existing
  existing=$(echo "$CURRENT" | jq -c ".records[] | select(.name == \"$fqdn\" and .type == \"$type\")" 2>/dev/null || true)

  if [ -n "$existing" ]; then
    local current_content
    current_content=$(echo "$existing" | jq -r '.content')
    if [ "$current_content" = "$content" ]; then
      echo "    OK (unchanged)"
      return
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
      echo "    [Dry-run] Would update $type $fqdn -> $content (currently: $current_content)"
      return
    fi

    RESP=$(curl -sf -X POST \
      "https://api.porkbun.com/api/json/v3/dns/editByNameType/$DOMAIN/$type/$sub" \
      -H 'Content-Type: application/json' \
      -d "{\"apikey\":\"$PORKBUN_API_KEY\",\"secretapikey\":\"$PORKBUN_SECRET_KEY\",\"content\":\"$content\",\"ttl\":\"$ttl\"}" \
      2>/dev/null || echo '{"status":"ERROR"}')

    STATUS=$(echo "$RESP" | jq -r '.status')
    if [ "$STATUS" = "SUCCESS" ]; then
      echo "    OK (updated)"
    else
      echo "    FAILED to update: $RESP" >&2
    fi
  else
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "    [Dry-run] Would create $type $fqdn -> $content"
      return
    fi

    RESP=$(curl -sf -X POST \
      "https://api.porkbun.com/api/json/v3/dns/create/$DOMAIN" \
      -H 'Content-Type: application/json' \
      -d "{\"apikey\":\"$PORKBUN_API_KEY\",\"secretapikey\":\"$PORKBUN_SECRET_KEY\",\"type\":\"$type\",\"name\":\"$sub\",\"content\":\"$content\",\"ttl\":\"$ttl\"}" \
      2>/dev/null || echo '{"status":"ERROR"}')

    STATUS=$(echo "$RESP" | jq -r '.status')
    if [ "$STATUS" = "SUCCESS" ]; then
      echo "    OK (created)"
    else
      echo "    FAILED to create: $RESP" >&2
    fi
  fi
}

delete_record() {
  local id="$1" name="$2" type="$3" reason="$4"
  echo "  Deleting $type $name (id: $id, reason: $reason)"
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "    [Dry-run] Would delete $type $name"
    return
  fi

  RESP=$(curl -sf -X POST \
    "https://api.porkbun.com/api/json/v3/dns/delete/$DOMAIN/$id" \
    -H 'Content-Type: application/json' \
    -d "{\"apikey\":\"$PORKBUN_API_KEY\",\"secretapikey\":\"$PORKBUN_SECRET_KEY\"}" \
    2>/dev/null || echo '{"status":"ERROR"}')

  STATUS=$(echo "$RESP" | jq -r '.status')
  if [ "$STATUS" = "SUCCESS" ]; then
    echo "    OK (deleted)"
  else
    echo "    FAILED to delete: $RESP" >&2
  fi
}

echo ""
echo "=== Cloud public A records ==="
echo "$DATA" | jq -r '.public.cloud[] | select(.ip != null and .cname == null) | "\(.subdomain) \(.ip)"' | while read -r sub ip; do
  sync_record "$sub" "A" "$ip" "600"
done

echo ""
echo "=== Cloud public CNAME records ==="
echo "$DATA" | jq -r '.public.cloud[] | select(.cname != null) | "\(.subdomain) \(.cname)"' | while read -r sub cname; do
  sync_record "$sub" "CNAME" "$cname" "600"
done

echo ""
echo "=== Homelab public CNAME records ==="
echo "$DATA" | jq -r '.public.homelab[] | "\(.subdomain) \(.cname)"' | while read -r sub cname; do
  sync_record "$sub" "CNAME" "$cname" "600"
done

if [ "$PRUNE" -eq 1 ]; then
  echo ""
  echo "=== Pruning mesh-only & stale Porkbun records ==="
  PRUNE_CANDIDATES=$(jq -n \
    --argjson current "$CURRENT" \
    --argjson data "$DATA" \
    --argjson pii "$PII" '
    $data.domain as $domain |
    [
      $domain,
      "*.\($domain)",
      "www.\($domain)",
      "\($pii.hosts.homelab1.name).\($domain)",
      "\($pii.hosts.cloud1.name).\($domain)",
      "_acme-challenge.\($domain)"
    ] as $protected |
    (
      [ $data.public.homelab[].subdomain | "\(.).\($domain)" ]
      + [ $data.public.cloud[].subdomain | "\(.).\($domain)" ]
    ) as $desired |
    [
      $current.records[] as $rec
      | select(
          ($rec.type != "NS")
          and (($protected | index($rec.name)) == null)
          and (($desired | index($rec.name)) == null)
        )
      | { id: $rec.id, name: $rec.name, type: $rec.type, content: $rec.content }
    ]
  ')

  PRUNE_COUNT=$(echo "$PRUNE_CANDIDATES" | jq 'length')
  echo "Found $PRUNE_COUNT records eligible for pruning."

  if [ "$PRUNE_COUNT" -gt 0 ]; then
    echo "$PRUNE_CANDIDATES" | jq -c '.[]' | while read -r record; do
      id=$(echo "$record" | jq -r '.id')
      name=$(echo "$record" | jq -r '.name')
      type=$(echo "$record" | jq -r '.type')
      delete_record "$id" "$name" "$type" "not in public services or protected list"
    done
  fi
fi

echo ""
echo "=== Porkbun sync complete ==="
