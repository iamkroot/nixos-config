#!/usr/bin/env bash
set -euo pipefail

: "${PORKBUN_API_KEY:?must be set}"
: "${PORKBUN_SECRET_KEY:?must be set}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

PII=$($NIX_BIN eval -f secrets/pii.nix --json)
SVCS=$($NIX_BIN eval -f secrets/services.nix --json)
DATA=$(jq -n --argjson pii "$PII" --argjson svcs "$SVCS" -f tools/dns-data.jq)

DOMAIN=$(echo "$DATA" | jq -r '.domain')

echo "Fetching current Porkbun records for $DOMAIN..."
CURRENT=$(curl -sf -X POST "https://api.porkbun.com/api/json/v3/dns/retrieve/$DOMAIN" \
  -H 'Content-Type: application/json' \
  -d "{\"apikey\":\"$PORKBUN_API_KEY\",\"secretapikey\":\"$PORKBUN_SECRET_KEY\"}")

echo "$CURRENT" | jq '.records[] | {name, type, content}' 2>/dev/null || echo "Could not parse current records"

sync_record() {
  local sub="$1" type="$2" content="$3" ttl="${4:-600}"
  echo "  Syncing $type $sub.$DOMAIN -> $content"

  EXISTS=$(echo "$CURRENT" | jq -e ".records[] | select(.name == \"$sub.$DOMAIN\" and .type == \"$type\")" >/dev/null 2>&1 && echo "yes" || echo "no")

  if [ "$EXISTS" = "yes" ]; then
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

echo ""
echo "=== Cloud A records ==="
echo "$DATA" | jq -r '.cloud[] | "\(.subdomain) \(.ip)"' | while read -r sub ip; do
  sync_record "$sub" "A" "$ip" "600"
done

echo ""
echo "=== Homelab CNAME records ==="
echo "$DATA" | jq -r '.homelab[] | "\(.subdomain) \(.cname)"' | while read -r sub cname; do
  sync_record "$sub" "CNAME" "$cname" "600"
done

echo ""
echo "=== Porkbun sync complete ==="
