#!/usr/bin/env bash
set -euo pipefail

ROUTER="${1:-router}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

PII=$($NIX_BIN eval -f secrets/pii.nix --json)
SVCS=$($NIX_BIN eval -f secrets/services.nix --json)
DATA=$(jq -n --argjson pii "$PII" --argjson svcs "$SVCS" -f tools/dns-data.jq)

# Build address= lines: router.local + all homelab services
ENTRIES=$(echo "$DATA" | jq -r '
  .domain as $d | .routerIp as $r |
  ["address=/router.local/\($r)"]
  + [.homelab[] | "address=/\(.subdomain).\($d)/\(.ip)"]
  | .[]')

COUNT=$(echo "$ENTRIES" | wc -l)
echo "Pushing $COUNT dnsmasq entries to $ROUTER..."

ssh "$ROUTER" "while uci -q delete dhcp.@dnsmasq[0].address; do :; done"

UCI_CMDS=$(echo "$ENTRIES" | while IFS= read -r entry; do
  printf "uci add_list dhcp.@dnsmasq[0].address='%s' && " "$entry"
done)

ssh "$ROUTER" "${UCI_CMDS}uci commit dhcp && /etc/init.d/dnsmasq restart"

echo "Done. $COUNT entries pushed to $ROUTER."
