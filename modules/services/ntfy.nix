{
  config,
  lib,
  pii,
  myUtils,
  ...
}:
let
  ntfySecretsDir = ../../secrets/ntfy;
  secretFiles =
    if builtins.pathExists ntfySecretsDir then
      builtins.attrNames (builtins.readDir ntfySecretsDir)
    else
      [ ];
  tokenFiles = builtins.filter (
    f: lib.hasPrefix "auth_token_" f && lib.hasSuffix ".age" f
  ) secretFiles;

  tokenSecrets = builtins.listToAttrs (
    map (f: {
      name = "ntfy/${lib.removeSuffix ".age" f}";
      value = { };
    }) tokenFiles
  );

  tokenEntries = map (
    f:
    let
      base = lib.removeSuffix ".age" f;
      label = lib.removePrefix "auth_token_" base;
    in
    "${pii.primaryUser}:${config.vaultix.placeholder."ntfy/${base}"}:${label}"
  ) tokenFiles;
  ntfyAuthTokensEnv = lib.concatStringsSep "," tokenEntries;
in
{
  imports = [
    (myUtils.mkCaddyModule "ntfy" { authelia = false; })
  ];

  vaultix.secrets = {
    "ntfy/admin_password_hash" = { };
  }
  // tokenSecrets;

  vaultix.templates."ntfy.env" = {
    mode = "0444";
    content = ''
      NTFY_AUTH_USERS=${pii.primaryUser}:${config.vaultix.placeholder."ntfy/admin_password_hash"}:admin
      ${lib.optionalString (tokenEntries != [ ]) "NTFY_AUTH_TOKENS=${ntfyAuthTokensEnv}"}
    '';
  };

  services.ntfy-sh = {
    enable = true;
    environmentFile = config.vaultix.templates."ntfy.env".path;
    settings = {
      base-url = "https://${config.infra.services.hostnames.ntfy}";
      listen-http = "127.0.0.1:${toString config.infra.services.ports.ntfy}";
      behind-proxy = true;
      attachment-cache-dir = "/var/lib/ntfy-sh/attachments";
      auth-file = "/var/lib/ntfy-sh/user.db";
      auth-default-access = "deny-all";
      enable-login = true;
      require-login = true;
      enable-signup = false;
      cache-file = "/var/lib/ntfy-sh/cache-file.db";
      auth-startup-queries = ''
        pragma journal_mode = WAL;
        pragma synchronous = normal;
        pragma busy_timeout = 15000;
      '';
    };
  };
}
