{
  config,
  pkgs,
  lib,
  pii,
  myUtils,
  ...
}:
let
  user = pii.primaryUser;
  gamingDatasets = import ../datasets/gaming.nix { inherit pii; };
  datasetMountpoints = lib.filter (m: m != "none") (
    lib.mapAttrsToList (name: ds: ds.mountpoint or "none") gamingDatasets
  );
  sunshineVirtualStart = pkgs.writeShellScriptBin "sunshine-virtual-start" ''
    set -euo pipefail

    WIDTH="''${SUNSHINE_CLIENT_WIDTH:-1920}"
    HEIGHT="''${SUNSHINE_CLIENT_HEIGHT:-1080}"
    FPS="''${SUNSHINE_CLIENT_FPS:-60}"
    FPS="''${FPS%.*}"

    # Set refresh rate and resolution on the virtual display to match client request
    ${pkgs.kdePackages.libkscreen}/bin/kscreen-doctor "output.Virtual-1.mode.''${WIDTH}x''${HEIGHT}@''${FPS}" 2>/dev/null || true
  '';

  sunshineVirtualStop = pkgs.writeShellScriptBin "sunshine-virtual-stop" ''
    true
  '';

  steamGamepadUI = pkgs.writeShellScriptBin "steam-gamepadui" ''
    export DISPLAY="''${DISPLAY:-:0}"
    export WAYLAND_DISPLAY="''${WAYLAND_DISPLAY:-wayland-0}"
    export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/1000}"
    export XDG_CURRENT_DESKTOP="''${XDG_CURRENT_DESKTOP:-KDE}"
    export XDG_SESSION_TYPE="''${XDG_SESSION_TYPE:-wayland}"
    if [ -z "''${XAUTHORITY:-}" ]; then
      XAUTH_FILE="$(ls -t "$XDG_RUNTIME_DIR"/xauth_* 2>/dev/null | head -n1)"
      [ -n "$XAUTH_FILE" ] && export XAUTHORITY="$XAUTH_FILE"
    fi
    exec ${pkgs.steam}/bin/steam -gamepadui "$@"
  '';
in
{
  imports = [
    (myUtils.mkCaddyModule "sunshine" {
      authelia = false;
      meshOnly = true;
      extraHostConfig.extraConfig = ''
        reverse_proxy https://127.0.0.1:${toString config.infra.services.ports.sunshine} {
          transport http {
            tls_insecure_skip_verify
          }
        }
      '';
    })
  ];

  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
  };

  programs.gamemode.enable = true;

  services.sunshine = {
    enable = true;
    autoStart = true;
    openFirewall = true; # Automatically opens TCP 47984-47990 & UDP 47998-48010
    capSysAdmin = false; # No security wrapper; prevents capability leakage to bubblewrap/Steam/Proton
    settings = {
      capture = "kwin";
      csrf_allowed_origins = "https://${config.infra.services.hostnames.sunshine},https://localhost:47990,https://127.0.0.1:47990";
    };
    applications = {
      env = {
        DISPLAY = ":0";
        WAYLAND_DISPLAY = "wayland-0";
        XDG_CURRENT_DESKTOP = "KDE";
        XDG_SESSION_TYPE = "wayland";
        PATH = "$(PATH):${
          lib.makeBinPath [
            sunshineVirtualStart
            sunshineVirtualStop
            steamGamepadUI
            pkgs.kdePackages.krfb
            pkgs.kdePackages.libkscreen
            pkgs.jq
            pkgs.procps
          ]
        }";
      };
      apps = [
        {
          name = "Desktop";
          image-path = "desktop.png";
          prep-cmd = [
            {
              do = "${sunshineVirtualStart}/bin/sunshine-virtual-start";
              undo = "${sunshineVirtualStop}/bin/sunshine-virtual-stop";
            }
          ];
        }
        {
          name = "Steam Big Picture";
          cmd = "${steamGamepadUI}/bin/steam-gamepadui";
          image-path = "steam.png";
          prep-cmd = [
            {
              do = "${sunshineVirtualStart}/bin/sunshine-virtual-start";
              undo = "${sunshineVirtualStop}/bin/sunshine-virtual-stop";
            }
          ];
        }
      ];
    };
  };

  systemd.user.services.krfb-virtualmonitor = {
    description = "KRFB Headless Virtual Display";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.kdePackages.krfb}/bin/krfb-virtualmonitor --name 1 --password dummy --port ${toString config.infra.services.ports.krfb} --resolution 1920x1080";
      Restart = "always";
      RestartSec = "2s";
    };
  };

  systemd.user.services.sunshine = {
    after = [ "krfb-virtualmonitor.service" ];
    wants = [ "krfb-virtualmonitor.service" ];
  };

  services.resolved = {
    enable = true;
    settings = {
      Resolve = {
        MulticastDNS = "yes";
      };
    };
  };
  networking.firewall.allowedUDPPorts = [ 5353 ]; # Open mDNS UDP port for local discovery

  environment.systemPackages = with pkgs; [
    libva-utils
    vulkan-tools
    mangohud
    kdePackages.krfb
    kdePackages.libkscreen
    procps
    sunshineVirtualStart
    sunshineVirtualStop
  ];

  users.users."${user}".extraGroups = [
    "input"
    "video"
    "render"
    "gamemode"
  ];

  systemd.tmpfiles.rules = map (dir: "d ${dir} 0755 ${user} users - -") datasetMountpoints;
}
