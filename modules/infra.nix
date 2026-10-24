{
  config,
  lib,
  pii,
  services,
  hostKey,
  myUtils,
  ...
}:
{
  options.infra.hostKey = lib.mkOption {
    type = lib.types.str;
    description = "Key into pii.hosts for this machine.";
  };

  options.infra.domain = lib.mkOption {
    type = lib.types.str;
    description = "Base domain name";
  };

  options.infra.services.ports = lib.mkOption {
    type = lib.types.attrsOf lib.types.port;
    default = { };
    description = "Service ports. Auto-populated from services.nix.";
  };

  options.infra.services.hostnames = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    description = "Mapping of my services to their hostnames.";
  };

  options.infra.services.catalog = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          enable = lib.mkEnableOption "Include in Account Center catalog" // {
            default = true;
          };
          name = lib.mkOption { type = lib.types.str; };
          url = lib.mkOption { type = lib.types.str; };
          icon = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
          };
          roles = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = {
              lldap_admin = "system_administrator";
            };
          };
        };
      }
    );
    default = { };
    description = "Account Center catalog entries.";
  };

  options.infra.dns = {
    adguard = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether AdGuard Home DNS integration is active.";
      };
      location = lib.mkOption {
        type = lib.types.str;
        default = "router2";
        description = "Location of AdGuard Home: 'homelab1' or 'local' to run locally on homelab1, or a host/appliance key in pii (e.g. 'router2') to proxy and sync certs.";
      };
      dotSubdomain = lib.mkOption {
        type = lib.types.str;
        default = "dns";
        description = "Subdomain used for DNS-over-TLS (DoT).";
      };
      syncCerts = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to automatically sync renewed wildcard TLS certs via ACME postRun.";
      };
    };
  };

  options.infra.keepGenerations = lib.mkOption {
    type = lib.types.int;
    default = 10;
    description = "Number of recent Nix profile generations to keep during garbage collection.";
  };

  config.infra.hostKey = hostKey;
  config.infra.domain = pii.primaryDomain;

  config.nixpkgs.overlays = [
    (final: prev: {
      # Workaround for nixpkgs #568705: eternal-terminal fails to build with abseil-cpp/protobuf in C++17 mode
      eternal-terminal = prev.eternal-terminal.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace CMakeLists.txt \
            --replace-fail "set(CMAKE_CXX_STANDARD 17)" "set(CMAKE_CXX_STANDARD 20)"
        '';
      });

      # Workaround for nixpkgs: authelia-web 4.39.28 has pnpmDepsHash mismatch on Linux
      authelia = myUtils.selfExpiringOverride {
        pkgs = prev;
        name = "authelia";
        strictlyNewer = true;
        minVersion = "4.39.28";
        localPkg = prev.authelia.override {
          authelia-web = prev.authelia.passthru.web.overrideAttrs (old: {
            pnpmDeps = prev.fetchPnpmDeps {
              inherit (old)
                pname
                version
                src
                sourceRoot
                ;
              pnpm = prev.pnpm_12;
              fetcherVersion = 4;
              hash = "sha256-B/Au9YICuRM6+J4DojFbXf2IEWC+j1jRsU68nn08Puk=";
            };
          });
        };
      };
    })
  ];

  config.infra.services.ports = lib.mkMerge (
    [ (lib.mapAttrs (_: s: lib.mkDefault (s.port or 0)) services) ]
    ++ (lib.mapAttrsToList (
      _: s: lib.mapAttrs (_: port: lib.mkDefault port) (s.extraPorts or { })
    ) services)
  );

  config.infra.services.hostnames = lib.mapAttrs (
    name: s: if s.subdomain != null then "${s.subdomain}.${config.infra.domain}" else null
  ) services;

  config.infra.services.catalog = lib.mapAttrs (
    name: s:
    let
      hostname = if s.subdomain != null then "${s.subdomain}.${config.infra.domain}" else null;
    in
    {
      enable = lib.mkDefault (
        (s.catalog.enable or true)
        && hostname != null
        && (config.services.caddy.virtualHosts ? "${hostname}")
      );
      name = lib.mkDefault (lib.toUpper (lib.substring 0 1 name) + lib.substring 1 (-1) name);
      url = lib.mkDefault (if hostname != null then "https://${hostname}" else "");
      icon = lib.mkDefault (
        let
          rawIcon = s.catalog.icon or null;
          iconVal = if rawIcon != null then rawIcon else name;
        in
        if lib.hasPrefix "http://" iconVal || lib.hasPrefix "https://" iconVal then
          iconVal
        else
          let
            hasExt =
              lib.hasSuffix ".svg" iconVal || lib.hasSuffix ".png" iconVal || lib.hasSuffix ".webp" iconVal;
            fileName = if hasExt then iconVal else "${iconVal}.svg";
          in
          "https://${config.infra.services.hostnames.icons}/${fileName}"
      );
      roles = lib.mkDefault (s.catalog.roles or { lldap_admin = "system_administrator"; });
    }
  ) services;

  config.services.caddy.virtualHosts = lib.mkMerge (
    lib.mapAttrsToList (
      name: s:
      let
        oldHost = "${s.subdomain}.${pii.oldDomain}";
        newHost = "${s.subdomain}.${config.infra.domain}";
      in
      lib.mkIf ((s.host == hostKey || hostKey == "homelab1") && s.subdomain != null) {
        "${oldHost}" = {
          extraConfig = "redir https://${newHost}{uri} 308";
        };
      }
    ) services
    ++ lib.optional (hostKey == "homelab1") {
      "${pii.oldDomain}" = {
        extraConfig = "redir https://${config.infra.domain}{uri} 308";
      };
    }
  );

  config.nix = {
    settings = {
      auto-optimise-store = lib.mkDefault true;
    };
    optimise.automatic = lib.mkDefault true;
    gc = {
      automatic = lib.mkDefault true;
      dates = lib.mkDefault "weekly";
    };
  };

  config.systemd.services.nix-gc = {
    script = lib.mkForce ''
      for profile in /nix/var/nix/profiles/system /nix/var/nix/profiles/per-user/*/profile /nix/var/nix/profiles/per-user/*/home-manager; do
        if [ -e "$profile" ]; then
          ${config.nix.package}/bin/nix-env --delete-generations +${toString config.infra.keepGenerations} --profile "$profile"
        fi
      done
      ${config.nix.package}/bin/nix-collect-garbage
    '';
  };

  options.infra.versions = lib.mkOption {
    type =
      let
        t = lib.types;
        sourceSpecSubmodule = t.submodule {
          freeformType = t.attrsOf t.anything;
          options = {
            repository = lib.mkOption {
              type = t.nullOr t.str;
              default = null;
              description = "Repository forge URI (e.g. github:owner/repo, gitea:domain/owner/repo).";
            };
            rev = lib.mkOption {
              type = t.nullOr t.str;
              default = null;
              description = "Git commit revision or tag.";
            };
            hash = lib.mkOption {
              type = t.nullOr t.str;
              default = null;
              description = "Fixed-output derivation SRI hash.";
            };
            forceFetchGit = lib.mkOption {
              type = t.nullOr t.bool;
              default = null;
              description = "Whether to force git fetch instead of archive tarball.";
            };
          };
        };

        serviceVersionSubmodule = t.submodule {
          freeformType = t.attrsOf (t.either serviceVersionSubmodule t.anything);
          options = {
            version = lib.mkOption {
              type = t.nullOr t.str;
              default = null;
              description = "Application or suite version string.";
            };
            src = lib.mkOption {
              type = t.nullOr sourceSpecSubmodule;
              default = null;
              description = "Source repository fetch specification for build-from-source derivations.";
            };
            repository = lib.mkOption {
              type = t.nullOr t.str;
              default = null;
              description = "Container image repository URI.";
            };
            tag = lib.mkOption {
              type = t.nullOr t.str;
              default = null;
              description = "Container image tag.";
            };
            digest = lib.mkOption {
              type = t.nullOr t.str;
              default = null;
              description = "Container image digest.";
            };
            hash = lib.mkOption {
              type = t.nullOr t.str;
              default = null;
              description = "Source code or derivation hash.";
            };
            rev = lib.mkOption {
              type = t.nullOr t.str;
              default = null;
              description = "Git commit revision.";
            };
          };
        };
      in
      t.attrsOf serviceVersionSubmodule;
    default = { };
    description = "Application and container versions extracted from versions.toml";
  };

  config.infra.versions = lib.mapAttrs (_: v: lib.mkDefault v) (
    builtins.fromTOML (builtins.readFile ../versions.toml)
  );
}
