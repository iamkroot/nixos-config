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

    # 1. Clean up any stale virtual monitor
    if [ -f /tmp/sunshine-krfb.pid ]; then
      kill "$(cat /tmp/sunshine-krfb.pid)" 2>/dev/null || true
      rm -f /tmp/sunshine-krfb.pid
    fi

    # 2. Spawn virtual display via KRFB
    ${pkgs.kdePackages.krfb}/bin/krfb-virtualmonitor --name "1" --password dummy --port ${toString config.infra.services.ports.krfb} --resolution "''${WIDTH}x''${HEIGHT}" &
    echo $! > /tmp/sunshine-krfb.pid

    # 3. Wait for KWin to register the new output
    sleep 2

    # 4. Set refresh rate and resolution via kscreen-doctor if needed
    ${pkgs.kdePackages.libkscreen}/bin/kscreen-doctor "output.Virtual-1.mode.''${WIDTH}x''${HEIGHT}@''${FPS}" 2>/dev/null || true

    # 5. Disable physical displays so Sunshine captures only the virtual output
    ${pkgs.kdePackages.libkscreen}/bin/kscreen-doctor --json 2>/dev/null | ${pkgs.jq}/bin/jq -r '.outputs[] | select(.name != "Virtual-1" and .connected == true) | .name' | while read -r out; do
      [ -n "$out" ] && ${pkgs.kdePackages.libkscreen}/bin/kscreen-doctor "output.''${out}.disable" 2>/dev/null || true
    done
  '';

  sunshineVirtualStop = pkgs.writeShellScriptBin "sunshine-virtual-stop" ''
    # 1. Re-enable physical displays
    ${pkgs.kdePackages.libkscreen}/bin/kscreen-doctor --json 2>/dev/null | ${pkgs.jq}/bin/jq -r '.outputs[] | select(.name != "Virtual-1" and .connected == true) | .name' | while read -r out; do
      [ -n "$out" ] && ${pkgs.kdePackages.libkscreen}/bin/kscreen-doctor "output.''${out}.enable" 2>/dev/null || true
    done

    # 2. Kill virtual display
    if [ -f /tmp/sunshine-krfb.pid ]; then
      kill "$(cat /tmp/sunshine-krfb.pid)" 2>/dev/null || true
      rm -f /tmp/sunshine-krfb.pid
    fi
    ${pkgs.procps}/bin/pkill -f krfb-virtualmonitor 2>/dev/null || true
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
    capSysAdmin = true; # Grants Wayland KMS framebuffer capture permissions
    settings = {
      capture = "kwin";
      csrf_allowed_origins = "https://${config.infra.services.hostnames.sunshine},https://localhost:47990,https://127.0.0.1:47990";
    };
    applications = {
      env = {
        PATH = "$(PATH):${
          lib.makeBinPath [
            sunshineVirtualStart
            sunshineVirtualStop
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
          cmd = "${pkgs.steam}/bin/steam -gamepadui";
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
