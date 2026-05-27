{
  config,
  lib,
  myUtils,
  pii,
  pkgs,
  ...
}:
let
  port = config.infra.services.ports."account-center";

  yamlFormat = pkgs.formats.yaml { };
  enabledServices = lib.filterAttrs (n: v: v.enable) config.infra.services.catalog;
  catalogData = {
    global_access = {
      lldap_admin = "system_administrator";
    };
    services = lib.mapAttrsToList (
      n: v:
      {
        name = v.name;
        url = v.url;
      }
      // lib.optionalAttrs (v.icon != null) { icon = v.icon; }
      // lib.optionalAttrs (v.roles != { }) { roles = v.roles; }
    ) enabledServices;
  };
  catalogFile = yamlFormat.generate "catalog.yaml" catalogData;
in
{
  imports = [
    (myUtils.mkCaddyModule "account-center" { authelia = false; })
  ];

  vaultix.secrets."account-center/sso_secret" = { };
  vaultix.templates."account-center.env" = {
    content = ''
      AC_OIDC_PROVIDER_URL=https://${config.infra.services.hostnames.auth}
      AC_OIDC_CLIENT_ID=${pii.secrets.authelia-account-center-client-id}
      AC_OIDC_CLIENT_SECRET=${config.vaultix.placeholder."account-center/sso_secret"}
      AC_INSTANCE_BASE_URL=https://${config.infra.services.hostnames."account-center"}
    '';
  };

  virtualisation.oci-containers.containers = {
    account-center = {
      image = "ghcr.io/icikowski/account-center:dev";
      ports = [ "127.0.0.1:${toString port}:8080" ];
      volumes = [
        "/var/lib/account-center:/data"
        "${catalogFile}:/data/catalog.yaml:ro"
      ];
      environmentFiles = [
        config.vaultix.templates."account-center.env".path
      ];
      extraOptions = [
        "--add-host=${config.infra.services.hostnames.auth}:host-gateway"
      ];
    };
  };

  system.activationScripts.accountCenterVolumes = ''
    mkdir -p /var/lib/account-center
    chmod 755 /var/lib/account-center
  '';
}
