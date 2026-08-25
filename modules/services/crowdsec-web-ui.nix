{
  config,
  pkgs,
  pii,
  myUtils,
  ...
}:
let
  lapiPort = toString config.infra.services.ports.crowdsec;
  webUiPort = toString config.infra.services.ports.crowdsec-web-ui;
in
{
  imports = [
    (myUtils.mkCaddyModule "crowdsec-web-ui" { authelia = true; })
  ];

  myAuthelia.accessRules = [
    {
      domain = config.infra.services.hostnames.crowdsec-web-ui;
      policy = "one_factor";
      subject = [
        "group:lldap_admin"
      ];
    }
  ];

  vaultix.secrets."crowdsec-web-ui-lapi-pwd" = {
    file = pii.secrets.crowdsec-web-ui-lapi-pwd;
    owner = "root";
    group = "root";
  };

  vaultix.templates."crowdsec-web-ui.env" = {
    content = ''
      CONFIG_AUTH_ENABLED=false
      CONFIG_INSTANCE_LAPI_URL=http://host.containers.internal:${lapiPort}
      CONFIG_INSTANCE_LAPI_AUTH_TYPE=password
      CONFIG_INSTANCE_LAPI_AUTH_USERNAME=crowdsec-web-ui
      CONFIG_INSTANCE_LAPI_AUTH_PASSWORD=${config.vaultix.placeholder."crowdsec-web-ui-lapi-pwd"}
    '';
  };

  systemd.services.crowdsec-register-web-ui = {
    description = "Register crowdsec-web-ui machine account in CrowdSec";
    after = [ "crowdsec.service" ];
    requires = [ "crowdsec.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "register-crowdsec-web-ui" ''
        if ! ${pkgs.crowdsec}/bin/cscli machines list -o json 2>/dev/null | ${pkgs.jq}/bin/jq -e '.[] | select(.machineId=="crowdsec-web-ui")' > /dev/null 2>&1; then
          ${pkgs.crowdsec}/bin/cscli machines add crowdsec-web-ui \
            -p "$(${pkgs.coreutils}/bin/cat ${config.vaultix.secrets."crowdsec-web-ui-lapi-pwd".path})" \
            -f /dev/null \
            --force
        fi
      '';
    };
  };

  systemd.services."podman-crowdsec-web-ui" = {
    after = [ "crowdsec-register-web-ui.service" ];
    requires = [ "crowdsec-register-web-ui.service" ];
  };

  virtualisation.oci-containers.containers."crowdsec-web-ui" = {
    image = "ghcr.io/theduffman85/crowdsec-web-ui:latest";
    ports = [ "127.0.0.1:${webUiPort}:3000" ];
    volumes = [
      "/var/lib/crowdsec-web-ui:/app/data"
    ];
    extraOptions = [
      "--add-host=host.containers.internal:host-gateway"
    ];
    environmentFiles = [
      config.vaultix.templates."crowdsec-web-ui.env".path
    ];
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/crowdsec-web-ui 0755 1000 1000 -"
  ];

  networking.firewall.interfaces."podman0".allowedTCPPorts = [
    config.infra.services.ports.crowdsec
  ];
}
