{ config, pii, ... }: {
  vaultix.secrets.syncplay_pwd = { };
  vaultix.secrets.syncplay_salt = { };

  services.syncplay = {
    enable = true;
    interfaceIpv4 = "0.0.0.0";
    ipv4Only = true;
    passwordFile = config.vaultix.secrets.syncplay_pwd.path;
    saltFile = config.vaultix.secrets.syncplay_salt.path;
    isolateRooms = true;
    permanentRooms = pii.syncplayRooms;
    roomsDBFile = "rooms.db";
    statsDBFile = "stats.db";
    useACMEHost = config.infra.services.hostnames.syncplay;
  };

  systemd.services.syncplay = {
    requires = [ "vaultix-activate.service" ];
    after = [ "vaultix-activate.service" ];
    serviceConfig = {
      # Filesystem isolation
      ProtectHome = true;
      ProtectSystem = "strict";
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectProc = "invisible";
      ProcSubset = "pid";

      # Kernel hardening
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;

      # Privilege restriction
      NoNewPrivileges = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
      CapabilityBoundingSet = "";

      # Network: only allow IPv4 TCP sockets
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_UNIX"
      ];

      # Misc
      RestrictNamespaces = true;
      RestrictRealtime = true;
      SystemCallArchitectures = "native";
      MemoryDenyWriteExecute = true;
    };
  };
}
