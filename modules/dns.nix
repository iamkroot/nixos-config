# Central DNS registry — generic module (no infra-specific data).
#
# Exports structured DNS data consumed by tools/ scripts.
# Derives from the unified `services` registry passed via specialArgs.
{
  config,
  lib,
  pii,
  services,
  ...
}:
let
  domain = config.infra.domain;
  ddnsSubdomain = pii.hosts.homelab1.name;
  routerIp = pii.router.localIp;

  # Only include services that have DNS enabled (default true for services without dns = false)
  dnsServices = lib.filterAttrs (_: s: (s.dns or true) == true) services;

  # Host is cloud if it has a publicIp; homelab otherwise
  homelabServices = lib.filterAttrs (_: s: !(pii.hosts.${s.host} ? publicIp)) dnsServices;
  cloudServices = lib.filterAttrs (_: s: pii.hosts.${s.host} ? publicIp) dnsServices;

  dnsData = {
    inherit domain ddnsSubdomain routerIp;
    homelab = lib.mapAttrsToList (name: s: {
      subdomain = s.subdomain or name;
      ip = pii.hosts.${s.host}.localIp;
      cname = "${pii.hosts.${s.host}.name}.${domain}";
    }) homelabServices;
    cloud = lib.mapAttrsToList (name: s: {
      subdomain = s.subdomain or name;
      ip = pii.hosts.${s.host}.publicIp;
    }) cloudServices;
  };
in
{
  options.infra.dns.data = lib.mkOption {
    type = lib.types.attrs;
    readOnly = true;
    default = dnsData;
    description = "Structured DNS data consumed by tools/ scripts.";
  };
}
