{
  inputs,
  pkgs,
  pii,
  ...
}:

{
  imports = [
    inputs.plasma-manager.homeModules.plasma-manager
  ];

  programs.plasma = {
    enable = true;

    # strict mode: If set to true, it will delete GUI-made changes on next rebuild
    # overrideConfig = true;

    workspace = {
      clickItemTo = "select"; # Double click to open files
      lookAndFeel = "org.kde.breezedark.desktop";
    };

    powerdevil = {
      AC = {
        turnOffDisplay = {
          idleTimeout = 300;
          idleTimeoutWhenLocked = "immediately";
        };
        autoSuspend = {
          action = "nothing";
          idleTimeout = null;
        };
      };
    };

    configFile."baloofilerc" = {
      "Basic Settings" = {
        "Indexing-Enabled" = false;
      };
    };

    configFile."krdprc" = {
      "RDP" = {
        enabled = true;
        user = pii.primaryUser;
      };
      "Graphics" = {
        H264CodecEnabled = true;
        HardwareEncodingEnabled = true;
      };
    };
  };
}
