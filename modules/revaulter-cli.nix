{
  config,
  pkgs,
  lib,
  pii,
  services,
  ...
}:

let
  revaulterPkg = pkgs.stdenv.mkDerivation rec {
    pname = "revaulter";
    version = "2.4.1";

    src = pkgs.fetchurl {
      url = "https://github.com/ItalyPaleAle/revaulter/releases/download/v${version}/revaulter-${version}-linux-amd64.tar.gz";
      hash = "sha256-qYv/eKi6KhdGlxrSGGR8Ti8PH3htJjYi5Ga3i/J9AnU=";
    };

    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin
      cp revaulter-cli $out/bin/
      chmod +x $out/bin/revaulter-cli
      runHook postInstall
    '';

    meta = with lib; {
      description = "Revaulter CLI tool";
      homepage = "https://github.com/ItalyPaleAle/revaulter";
      license = licenses.mit;
      platforms = [ "x86_64-linux" ];
    };
  };

  commonScriptInit = ''
    source ${config.vaultix.templates."revaulter-cli.env".path}

    revaulter() {
      ${revaulterPkg}/bin/revaulter-cli "$@" \
        --server "$REVAULTER_SERVER" \
        --no-trust-store \
        --request-key "$REVAULTER_REQUEST_KEY"
    }
  '';
in
{
  vaultix.secrets."revaulter/request_key" = { };

  # We generate an environment file that contains the secrets
  vaultix.templates."revaulter-cli.env" = {
    content = ''
      REVAULTER_SERVER="https://${config.infra.services.hostnames.revaulter}"
      REVAULTER_REQUEST_KEY=${config.vaultix.placeholder."revaulter/request_key"}
    '';
  };

  # CLI wrapper scripts for revaulter-zfs setup and unlocking
  environment.systemPackages = [
    revaulterPkg
    (pkgs.writeShellScriptBin "revaulter-zfs-unlock" ''
      set -euo pipefail

      if [ "$#" -ne 1 ]; then
        echo "Usage: revaulter-zfs-unlock <dataset>"
        exit 1
      fi

      DATASET_NAME=$1
      JSON_KEY_FILE="/etc/revaulter/keys/$DATASET_NAME.json"

      if [ ! -f "$JSON_KEY_FILE" ]; then
        echo "Error: Key file $JSON_KEY_FILE not found."
        exit 1
      fi

      KEYSTATUS=$(zfs get -H -o value keystatus "$DATASET_NAME" || true)
      if [ "$KEYSTATUS" = "available" ]; then
        echo "Key already loaded for '$DATASET_NAME'."
        exit 0
      fi

      ${commonScriptInit}

      cat "$JSON_KEY_FILE" \
        | revaulter decrypt \
          --json - \
          --note "ZFS dataset $DATASET_NAME" \
          --format raw \
        | zfs load-key "$DATASET_NAME"
        
      echo "Successfully unlocked $DATASET_NAME"
    '')

    (pkgs.writeShellScriptBin "revaulter-zfs-wrap" ''
      set -euo pipefail

      if [ "$#" -ne 1 ]; then
        echo "Usage: revaulter-zfs-wrap <dataset>"
        exit 1
      fi

      DATASET_NAME=$1
      JSON_KEY_FILE="/etc/revaulter/keys/$DATASET_NAME.json"
      REVAULTER_KEY_LABEL="zfs-$(hostname)"
      REVAULTER_AAD="$(hostname):$DATASET_NAME"

      mkdir -p "/etc/revaulter/keys/$(dirname "$DATASET_NAME")"
      chmod 0700 "/etc/revaulter/keys/$(dirname "$DATASET_NAME")"

      ${commonScriptInit}

      # Ask for the passphrase or read from stdin if piped
      if [ -t 0 ]; then
        read -s -p "Enter dataset keyphrase to wrap: " KEYPHRASE
        echo
        INPUT="$KEYPHRASE"
      else
        INPUT=$(cat)
      fi

      printf "%s" "$INPUT" | revaulter encrypt \
          --algorithm aes-256-gcm \
          --key-label "$REVAULTER_KEY_LABEL" \
          --input - \
          --aad "$(printf "%s" "$REVAULTER_AAD" | base64 -w0)" \
          --note "ZFS dataset $DATASET_NAME" \
          --format json \
      > "$JSON_KEY_FILE"

      echo "Wrapped key saved to $JSON_KEY_FILE"
    '')
  ];

  # Ensure the directory exists so Vaultix can write to it without failing
  systemd.tmpfiles.rules = [
    "d /etc/revaulter/cli 0700 root root -"
  ];
  environment.etc."revaulter/cli/trust.json".source =
    pii.hosts.${services.revaulter.host}.revaulterTrust;

  # Use Vaultix template to write the decrypted key directly to a persistent path
  vaultix.templates."revaulter-request-key" = {
    content = "${config.vaultix.placeholder."revaulter/request_key"}";
    path = "/etc/revaulter/cli/request_key";
    mode = "0400";
  };

  # --- INITRD SUPPORT ---
  # Read the request key from the target machine's /etc.
  boot.initrd.secrets = {
    "/etc/revaulter/cli/request_key" = "/etc/revaulter/cli/request_key";
  };

  # If the user has committed zroot.json to secrets/revaulter/..., bundle it natively:
  boot.initrd.systemd.contents = lib.mkIf (builtins.pathExists pii.storage.zroot.revaulterKey) {
    "/etc/revaulter/keys/${pii.storage.zroot.name}.json".source = pii.storage.zroot.revaulterKey;
  };

  # Bundle required binaries and CA certs into initrd
  boot.initrd.systemd.storePaths = [
    revaulterPkg
    pkgs.socat
    pkgs.gnugrep
    pkgs.coreutils
    "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
  ];

  boot.initrd.systemd.services."revaulter-unlock-${pii.storage.zroot.name}" =
    lib.mkIf (builtins.pathExists pii.storage.zroot.revaulterKey)
      {
        description = "Unlock ZFS ${pii.storage.zroot.name} via Revaulter";
        # Run concurrently with the ZFS import process
        wantedBy = [ "zfs-import-${pii.storage.zroot.name}.service" ];
        after = [
          "systemd-networkd.service"
          "systemd-resolved.service"
        ];
        requires = [ "network-online.target" ];
        path = [
          revaulterPkg
          pkgs.socat
          pkgs.gnugrep
          pkgs.coreutils
        ];
        environment = {
          SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
        };
        unitConfig.DefaultDependencies = false;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          set -euo pipefail

          echo "[revaulter-zfs] Starting Revaulter ZFS unlock process..."

          # Wait for the ZFS ask-password prompt to appear
          echo "[revaulter-zfs] Waiting for ${pii.storage.zroot.name} password prompt from systemd..."
          while ! grep -q "${pii.storage.zroot.name}" /run/systemd/ask-password/ask.* 2>/dev/null; do
            sleep 1
          done

          echo "[revaulter-zfs] Waiting for network and DNS to reach Revaulter server..."
          while ! socat /dev/null TCP:"${config.infra.services.hostnames.revaulter}:443,connect-timeout=2" >/dev/null 2>&1; do
            sleep 1
          done

          # Find the socket path
          for p in /run/systemd/ask-password/ask.*; do
            if grep -q "${pii.storage.zroot.name}" "$p"; then
              SOCKET=$(grep '^Socket=' "$p" | cut -d= -f2)
              break
            fi
          done

          if [ -z "''${SOCKET:-}" ]; then
            echo "[revaulter-zfs] Error: Could not find systemd-ask-password socket for ${pii.storage.zroot.name}."
            exit 1
          fi

          echo "[revaulter-zfs] Found prompt socket at $SOCKET. Requesting decryption from Revaulter server..."
          echo "[revaulter-zfs] Please approve the decryption request on your device..."

          while ! PASSWORD=$(revaulter-cli decrypt \
              --server "https://${config.infra.services.hostnames.revaulter}" \
              --no-trust-store \
              --request-key "$(cat /etc/revaulter/cli/request_key)" \
              --json /etc/revaulter/keys/${pii.storage.zroot.name}.json --format raw); do
            echo "[revaulter-zfs] Decryption failed or denied! Retrying in 5 seconds..."
            sleep 5
          done

          echo "[revaulter-zfs] Decryption approved! Feeding password to systemd..."
          printf "+%s" "$PASSWORD" | socat - "UNIX-SENDTO:$SOCKET"

          echo "[revaulter-zfs] ${pii.storage.zroot.name} unlocked successfully via Revaulter!"
        '';
      };
}
