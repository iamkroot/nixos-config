{ lib, ... }:
{
  mkPortOption =
    defaultPort: description:
    lib.mkOption {
      type = lib.types.port;
      default = defaultPort;
      description = description;
    };
  # for LDAP stuff
  domainToBaseDN =
    domain: lib.concatStringsSep "," (map (part: "dc=${part}") (lib.splitString "." domain));

  # use via `imports = [(mkCaddyModule "foobar")]`
  mkCaddyModule =
    name:
    {
      authelia ? false,
      extraHostConfig ? { },
      portKey ? name,
    }:
    { config, ... }:
    let
      hostname = config.infra.services.hostnames."${name}";
      port = config.infra.services.ports."${portKey}";
      userExtraConfig = extraHostConfig.extraConfig or null;
    in
    {
      services.caddy.virtualHosts."${hostname}" = lib.mkMerge [
        {
          useACMEHost = config.infra.domain;
          extraConfig = ''
            ${if authelia then "import authelia" else ""}
            ${if userExtraConfig != null then userExtraConfig else "reverse_proxy 127.0.0.1:${toString port}"}
          '';

          logFormat = lib.mkDefault ''
            output file /var/log/caddy/access-${hostname}.log {
              roll_size 50mb
              roll_keep 5
            }
          '';
        }
        (builtins.removeAttrs extraHostConfig [ "extraConfig" ])
      ];
    };

  # Build an Authelia OIDC client attrset with sensible defaults.
  # Auto-derives client_id, client_secret, client_name from pii.authelia."${name}"
  # Defaults: public=false, authorization_policy="one_factor", userinfo_signed_response_alg="none", token_endpoint_auth_method="client_secret_post"
  # Set any default to null to remove it.
  # use via `myAuthelia.oidcClients = [(myUtils.mkAutheliaOIDC pii "forgejo" { redirect_uris = [...]; })]`
  mkAutheliaOIDC =
    pii: name: overrides:
    let
      capitalize =
        s:
        let
          len = builtins.stringLength s;
        in
        lib.toUpper (builtins.substring 0 1 s) + builtins.substring 1 (len - 1) s;

      defaults = {
        client_id = pii.authelia.${name}.client-id;
        client_secret = pii.authelia.${name}.client-secret;
        client_name = capitalize name;
        public = false;
        authorization_policy = "one_factor";
        userinfo_signed_response_alg = "none";
        token_endpoint_auth_method = "client_secret_post";
      };
      raw = defaults // overrides;
    in
    lib.filterAttrs (_: v: v != null) raw;

  # Self-expiring package override helper.
  # Emits a Nix evaluation warning when nixpkgs catches up to or exceeds the local package version,
  # automatically switching to the nixpkgs version.
  selfExpiringOverride =
    {
      pkgs,
      name,
      localPkg,
      minVersion ? (localPkg.version or "0.0.0"),
      strictlyNewer ? false,
      message ? null,
    }:
    let
      upstreamPkg = pkgs.${name} or null;
      upstreamVersion = if upstreamPkg != null then (upstreamPkg.version or "0.0.0") else "0.0.0";
      hasUpstream =
        if upstreamPkg == null then
          false
        else if strictlyNewer then
          lib.versionOlder minVersion upstreamVersion
        else
          lib.versionAtLeast upstreamVersion minVersion;
      defaultMessage = ''
        Package '${name}' (version ${upstreamVersion}) in nixpkgs is now ${
          if strictlyNewer then "newer than" else ">= required version"
        } ${minVersion}.
        The local override can now be safely removed in favor of pkgs.${name}.
      '';
      msg = if message != null then message else defaultMessage;
    in
    lib.warnIf hasUpstream msg (if hasUpstream then upstreamPkg else localPkg);
}
