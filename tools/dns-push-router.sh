#!/usr/bin/env bash
set -euo pipefail

ROUTER="${1:-router}"

DATA=$($NIX_BIN eval '.?submodules=1#nixosConfigurations.'"$NIXOS_HOST"'.config.infra.dns.data' \
  --json --extra-experimental-features "nix-command flakes")



# Build address= lines: router.local + all homelab services
ENTRIES=$(echo "$DATA" | jq -r '
  ["address=/router.local/\(.routerIp)"]
  + [.homelab[] | "address=/\(.subdomain).\(.domain)/\(.ip)"]
  | .[]')

COUNT=$(echo "$ENTRIES" | wc -l)
echo "Pushing $COUNT dnsmasq entries to $ROUTER..."

ssh "$ROUTER" "while uci -q delete dhcp.@dnsmasq[0].address; do :; done"

UCI_CMDS=$(echo "$ENTRIES" | while IFS= read -r entry; do
  printf "uci add_list dhcp.@dnsmasq[0].address='%s' && " "$entry"
done)

ssh "$ROUTER" "${UCI_CMDS}uci commit dhcp && /etc/init.d/dnsmasq restart"

echo "Done. $COUNT entries pushed to $ROUTER."
