# dns-data.jq — Derive DNS records from pii.nix + services.nix JSON.
#
# Usage:
#   jq -n --argjson pii "$PII" --argjson svcs "$SVCS" -f tools/dns-data.jq
#
# Expects $pii and $svcs as top-level variables (--argjson).

def domain: $pii.primaryDomain;
def router_ip: $pii.router.localIp;
def ddns_sub: $pii.hosts.homelab1.name;
def is_cloud(h): $pii.hosts[h] | has("publicIp");

$svcs | to_entries
| map(select(.value.dns != false))
| {
    domain: domain,
    ddnsSubdomain: ddns_sub,
    routerIp: router_ip,
    homelab: [
      .[]
      | select(is_cloud(.value.host) | not)
      | {
          subdomain: (.value.subdomain // .key),
          ip:    $pii.hosts[.value.host].localIp,
          cname: "\($pii.hosts[.value.host].name).\(domain)"
        }
    ],
    cloud: (
      [
        .[]
        | select(is_cloud(.value.host))
        | {
            subdomain: (.value.subdomain // .key),
            ip: $pii.hosts[.value.host].publicIp
          }
      ] + [
        $pii.hosts[]
        | select(has("publicIp"))
        | {
            subdomain: .name,
            ip: .publicIp
          }
      ]
    )
  }
