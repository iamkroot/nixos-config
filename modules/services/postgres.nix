{
  config,
  pkgs,
  lib,
  ...
}:

{
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_18;

    settings = {
      port = config.infra.services.ports.postgres;
      listen_addresses = lib.mkForce "127.0.0.1";

      # --- Memory (conservative for shared homelab) ---
      shared_buffers = "128MB";
      work_mem = "16MB";
      maintenance_work_mem = "64MB";
      wal_buffers = "16MB";

      # --- Auth ---
      password_encryption = "scram-sha-256";

      # --- Write performance ---
      checkpoint_completion_target = 0.9;
      # Safe on ZFS (COW filesystem) — saves ~30% write I/O
      full_page_writes = "off";
    };

    authentication = pkgs.lib.mkOverride 10 ''
      # Unix socket: OS user must match DB role
      local all all peer
      # TCP loopback: require password (scram-sha-256)
      host all all 127.0.0.1/32 scram-sha-256
      host all all ::1/128 scram-sha-256
    '';
  };
}
