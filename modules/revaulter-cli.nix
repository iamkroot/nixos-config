{
  config,
  pkgs,
  lib,
  ...
}:

let
  revaulterPkg = pkgs.stdenv.mkDerivation rec {
    pname = "revaulter";
    version = "2.1.3";

    src = pkgs.fetchurl {
      url = "https://github.com/ItalyPaleAle/revaulter/releases/download/v${version}/revaulter-${version}-linux-amd64.tar.gz";
      hash = "sha256-7Cz8m5Qyo7zH0iwyhfPLNzvxuhvd5iObv1ZCDFroN3A=";
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

    mkdir -p /etc/revaulter/cli
    chmod 0700 /etc/revaulter/cli
    if [ ! -f /etc/revaulter/cli/trust.json ]; then
      ${revaulterPkg}/bin/revaulter-cli trust \
        --server "$REVAULTER_SERVER" \
        --trust-store /etc/revaulter/cli/trust.json \
        --request-key "$REVAULTER_REQUEST_KEY"
    fi

    revaulter() {
      ${revaulterPkg}/bin/revaulter-cli "$@" \
        --server "$REVAULTER_SERVER" \
        --trust-store /etc/revaulter/cli/trust.json \
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
        INPUT=$(echo -n "$KEYPHRASE")
      else
        INPUT=$(cat)
      fi

      echo -n "$INPUT" | revaulter encrypt \
          --algorithm aes-256-gcm \
          --key-label "$REVAULTER_KEY_LABEL" \
          --input - \
          --aad "$(echo -n "$REVAULTER_AAD" | base64 -w0)" \
          --note "ZFS dataset $DATASET_NAME" \
          --format json \
      > "$JSON_KEY_FILE"

      echo "Wrapped key saved to $JSON_KEY_FILE"
    '')
  ];
}
