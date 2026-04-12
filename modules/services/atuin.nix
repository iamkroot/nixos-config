{
  config,
  pkgs,
  lib,
  pii,
  ...
}:

{
  networking.firewall.allowedTCPPorts = [ config.infra.services.ports.atuin ];

  services.atuin = {
    enable = true;
    host = "0.0.0.0";
    port = config.infra.services.ports.atuin;
    openRegistration = false;

    # Disable the default local PostgreSQL database
    database.createLocally = false;
  };

  systemd.services.atuin = {
    # Point Atuin to a local SQLite file
    environment = {
      ATUIN_DB_URI = lib.mkForce "sqlite:///var/lib/atuin/atuin.db";
    };
    serviceConfig = {
      # systemd will automatically create /var/lib/atuin and ensure the
      # Atuin dynamic user has the correct read/write permissions.
      StateDirectory = "atuin";
    };
  };
}
