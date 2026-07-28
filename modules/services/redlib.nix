{
  config,
  lib,
  pkgs,
  ...
}:

let
  src = pkgs.fetchFromGitHub {
    owner = "redlib-org";
    repo = "redlib";
    rev = "a4d36e954cf1bd64f209cd8868c5a29edc81b374";
    hash = "sha256-siyD6A12UALQIV7BMd7zu1TaojleTEYtpxPszuhx1/Y=";
  };
  redlib-latest = pkgs.redlib.overrideAttrs (oldAttrs: {
    version = "0.36.0-unstable-2026-05-13";
    inherit src;
    cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
      inherit src;
      name = "redlib-0.36.0-unstable-2026-05-13-vendor";
      hash = "sha256-eO3c7rlFna3DuO31etJ6S4c7NmcvgvIWZ1KVkNIuUqQ=";
    };
    # BoringSSL (via boring-sys2) needs cmake, go, git, perl, and libclang for bindgen
    nativeBuildInputs =
      (oldAttrs.nativeBuildInputs or [ ])
      ++ (with pkgs; [
        cmake
        go
        perl
        git
        rustPlatform.bindgenHook
      ]);
    checkFlags = (oldAttrs.checkFlags or [ ]) ++ [
      "--skip=oauth::tests::test_generic_web_backend"
      "--skip=oauth::tests::test_mobile_spoof_backend"
    ];
  });
  domain = config.infra.services.hostnames.redlib;
in
{
  services.redlib = {
    enable = true;
    package = redlib-latest;
    port = config.infra.services.ports.redlib;
    # Expose to local network
    openFirewall = true;
    settings = {
      REDLIB_DEFAULT_USE_HLS = "on";
      REDLIB_DEFAULT_SHOW_NSFW = "on";
      REDLIB_DEFAULT_HIDE_HLS_NOTIFICATION = "on";
    };
  };
  services.caddy.virtualHosts."${domain}" = {
    useACMEHost = config.infra.domain;
    extraConfig = ''
      # Match ClaudeBot and other common AI scrapers
      @aiBots {
        header User-Agent *ClaudeBot*
        header User-Agent *GPTBot*
        header User-Agent *CCBot*
        header User-Agent *anthropic-ai*
        header User-Agent *OmgiliBot*
      }

      # Drop the connection or return a 403 Forbidden
      respond @aiBots "AI Scraping Blocked" 403
      respond /robots.txt "User-agent: ClaudeBot\nDisallow: /\n\nUser-agent: GPTBot\nDisallow: /" 200

      reverse_proxy 127.0.0.1:${toString config.infra.services.ports.anubis_redlib} {
        header_up X-Real-IP {client_ip}
      }
    '';
    logFormat = ''
      output file /var/log/caddy/access-${domain}.log {
        roll_size 50mb
        roll_keep 5
      }
    '';
  };

  # Anubis Middleware
  services.anubis.instances."redlib" = {
    enable = true;
    settings = {
      TARGET = "http://127.0.0.1:${toString config.infra.services.ports.redlib}";

      BIND_NETWORK = "tcp";
      BIND = "127.0.0.1:${toString config.infra.services.ports.anubis_redlib}";

      # Anubis needs to know your domain context to safely issue cookies
      # and handle redirects after the PoW challenge is solved.
      REDIRECT_DOMAINS = domain;
      COOKIE_DOMAIN = domain;

      # 5 or 6 is usually a good sweet spot
      # for keeping scrapers out without hanging older devices.
      DIFFICULTY = 6;
    };
  };

}
