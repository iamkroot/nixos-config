{
  config,
  pkgs,
  myUtils,
  ...
}:

let
  v = config.infra.versions.redlib;
  src = pkgs.fetchFromGitHub {
    owner = v.owner or "redlib-org";
    repo = v.repo or "redlib";
    inherit (v) rev hash;
  };
  redlib-latest = pkgs.redlib.overrideAttrs (oldAttrs: {
    inherit (v) version;
    inherit src;
    cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
      inherit src;
      name = "redlib-${v.version}-vendor";
      hash = v.cargoHash;
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
  redlibPkg = myUtils.selfExpiringOverride {
    inherit pkgs;
    name = "redlib";
    localPkg = redlib-latest;
  };
  domain = config.infra.services.hostnames.redlib;
in
{
  imports = [
    (myUtils.mkCaddyModule "redlib" {
      authelia = false;
      meshOnly = true;
      extraHostConfig = {
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
      };
    })
  ];

  services.redlib = {
    enable = true;
    package = redlibPkg;
    port = config.infra.services.ports.redlib;
    # Expose to local network
    openFirewall = true;
    settings = {
      REDLIB_DEFAULT_USE_HLS = "on";
      REDLIB_DEFAULT_SHOW_NSFW = "on";
      REDLIB_DEFAULT_HIDE_HLS_NOTIFICATION = "on";
    };
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
