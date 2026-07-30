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

if [ "$DRY_RUN" -eq 1 ]; then
  echo "Dry run: would push $COUNT hosts entries to $ROUTER in /etc/kroot.hosts:"
  echo "$HOSTS_ENTRIES" | sed 's/^/  /'
  exit 0
fi

echo "Pushing $COUNT dnsmasq entries to $ROUTER via /etc/kroot.hosts..."

ssh "$ROUTER" '
  cat > /tmp/kroot.hosts.new
  if cmp -s /etc/kroot.hosts /tmp/kroot.hosts.new 2>/dev/null; then
    rm /tmp/kroot.hosts.new
    echo "No changes needed."
    exit 0
  fi
  mv /tmp/kroot.hosts.new /etc/kroot.hosts
  
  # Ensure the configuration is hooked into dnsmasq
  if ! uci -q show dhcp.@dnsmasq[0].addnhosts 2>/dev/null | grep -q "/etc/kroot.hosts"; then
    uci add_list dhcp.@dnsmasq[0].addnhosts="/etc/kroot.hosts"
    uci commit dhcp
    /etc/init.d/dnsmasq restart
  else
    # Soft reload is much faster and clears cache without dropping queries
    killall -q -HUP dnsmasq || /etc/init.d/dnsmasq reload
  fi
' <<< "$HOSTS_ENTRIES"

echo "Done. $COUNT entries pushed to $ROUTER."
