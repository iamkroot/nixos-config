#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=0
ROUTER="router"

while [[ "$#" -gt 0 ]]; do
  case $1 in
    --dry-run) DRY_RUN=1; shift ;;
    *) ROUTER="$1"; shift ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

NIX_BIN="${NIX_BIN:-nix}"
PII=$($NIX_BIN eval -f secrets/pii.nix --json)
SVCS=$($NIX_BIN eval --json --impure --expr 'let flake = builtins.getFlake (toString ./.); in (flake.inputs.nixpkgs.lib.evalModules { modules = [ ./modules/services-schema.nix ]; }).config.myServices')
DATA=$(jq -n --argjson pii "$PII" --argjson svcs "$SVCS" -f tools/dns-data.jq)

# Build hosts file entries: router.local + all homelab services
HOSTS_ENTRIES=$(echo "$DATA" | jq -r '
  .domain as $d | .routerIp as $r |
  ["\($r) router.local"]
  + [.homelab[] | "\(.ip) \(.subdomain).\($d)"]
  | .[]')

COUNT=$(echo "$HOSTS_ENTRIES" | wc -l)

# Build AdGuard Home rewrite rules: rewrite homelab subdomains to local IP for LAN clients only
ADGUARD_JSON=$(echo "$DATA" | jq -c '
  .domain as $d |
  {
    rules: [.homelab[] | "||\(.subdomain).\($d)^$dnsrewrite=\(.ip),client=LAN"]
  }
')

if [ "$DRY_RUN" -eq 1 ]; then
  echo "Dry run: would push $COUNT hosts entries to $ROUTER in /etc/kroot.hosts:"
  echo "$HOSTS_ENTRIES" | sed 's/^/  /'
  echo ""
  echo "Dry run: would push AdGuard Home split-DNS rewrite rules:"
  echo "$ADGUARD_JSON" | jq .
  exit 0
fi

echo "Pushing $COUNT dnsmasq entries to $ROUTER via /etc/kroot.hosts..."

ssh "$ROUTER" "
  cat > /tmp/kroot.hosts.new
  if ! cmp -s /etc/kroot.hosts /tmp/kroot.hosts.new 2>/dev/null; then
    mv /tmp/kroot.hosts.new /etc/kroot.hosts
    grep -q '^/etc/kroot.hosts' /etc/sysupgrade.conf 2>/dev/null || echo '/etc/kroot.hosts' >> /etc/sysupgrade.conf

    if ! uci -q show dhcp.@dnsmasq[0].addnhosts 2>/dev/null | grep -q '/etc/kroot.hosts'; then
      uci add_list dhcp.@dnsmasq[0].addnhosts='/etc/kroot.hosts'
      uci commit dhcp
      /etc/init.d/dnsmasq restart
    else
      killall -q -HUP dnsmasq || /etc/init.d/dnsmasq reload
    fi
  else
    rm -f /tmp/kroot.hosts.new
  fi

  # Sync AdGuard Home client-conditional split rewrites if AdGuard is active
  if curl -sf http://127.0.0.1:3000/control/status >/dev/null 2>&1; then
    echo 'Syncing AdGuard Home client=LAN split-DNS rewrite rules...'
    # Ensure persistent client 'LAN' exists for the local subnet
    curl -sf -X POST -H 'Content-Type: application/json' http://127.0.0.1:3000/control/clients/add \
      -d '{\"name\":\"LAN\",\"ids\":[\"192.168.1.0/24\"],\"filtering_enabled\":true,\"use_global_settings\":true}' >/dev/null 2>&1 || \
    curl -sf -X POST -H 'Content-Type: application/json' http://127.0.0.1:3000/control/clients/update \
      -d '{\"name\":\"LAN\",\"data\":{\"name\":\"LAN\",\"ids\":[\"192.168.1.0/24\"],\"filtering_enabled\":true,\"use_global_settings\":true}}' >/dev/null 2>&1

    # Remove [/kroot.dev/] from upstream_dns if present so WAN queries fall through to public DNS
    if grep -q '\[/kroot.dev/\]' /etc/adguardhome/adguardhome.yaml 2>/dev/null; then
      sed -i '/\[\/kroot.dev\/\]/d' /etc/adguardhome/adguardhome.yaml
      /etc/init.d/adguardhome restart
    fi

    # Push rewrite rules and flush cache
    curl -sf -X POST -H 'Content-Type: application/json' http://127.0.0.1:3000/control/filtering/set_rules \
      -d '$ADGUARD_JSON' >/dev/null
    curl -sf -X POST http://127.0.0.1:3000/control/cache_clear >/dev/null
    echo 'AdGuard Home split-DNS sync complete.'
  fi
" <<< "$HOSTS_ENTRIES"

echo "Done. $COUNT entries pushed to $ROUTER."
