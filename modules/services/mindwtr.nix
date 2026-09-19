{
  config,
  pkgs,
  pii,
  myUtils,
  ...
}:
let
  cloudPort = config.infra.services.ports.mindwtr;
  hostname = config.infra.services.hostnames.mindwtr;

  mindwtr-web-image = pkgs.dockerTools.pullImage {
    imageName = "ghcr.io/dongdongbh/mindwtr-app";
    imageDigest = "sha256:f6993a18e5f547a4df3ec941f94e10a74cf1287598ad7b21dca4a8478c950998";
    hash = "sha256-ANxGmUqu58E4zn/ecu+SIFSdr0+/zpWh0MFR/zsYT8A=";
    finalImageName = "mindwtr-app";
    finalImageTag = "1.3.1";
  };

  # extract the static files from docker image
  mindwtr-web =
    pkgs.runCommand "mindwtr-web-1.3.1"
      {
        nativeBuildInputs = [
          pkgs.gnutar
          pkgs.gzip
          pkgs.jq
        ];
      }
      ''
        mkdir -p root
        tar -C root -xf ${mindwtr-web-image}
        mkdir -p $out
        for layer in $(cat root/manifest.json | jq -r ".[0].Layers[]"); do
          tar -C $out -xf "root/$layer" usr/share/nginx/html 2>/dev/null || true
        done
        mv $out/usr/share/nginx/html/* $out/
        rm -rf $out/usr
      '';
in
{
  imports = [
    (myUtils.mkCaddyModule "mindwtr" {
      authelia = false;
      extraHostConfig = {
        extraConfig = ''
          handle /v1/* {
            reverse_proxy 127.0.0.1:${toString cloudPort}
          }
          handle /health {
            reverse_proxy 127.0.0.1:${toString cloudPort}
          }
          handle /ready {
            reverse_proxy 127.0.0.1:${toString cloudPort}
          }
          handle /assets/* {
            root * ${mindwtr-web}
            header Cache-Control "public, max-age=31536000, immutable"
            file_server
          }
          handle {
            root * ${mindwtr-web}
            try_files {path} /index.html
            file_server
          }
        '';
      };
    })
  ];

  vaultix.secrets.mindwtr_cloud_auth_tokens = {
    file = pii.secrets.mindwtr-auth-tokens;
  };

  vaultix.templates."mindwtr.env" = {
    content = ''
      MINDWTR_CLOUD_AUTH_TOKENS=${config.vaultix.placeholder.mindwtr_cloud_auth_tokens}
      MINDWTR_CLOUD_CORS_ORIGIN=https://${hostname}
    '';
  };

  virtualisation.oci-containers = {
    backend = "podman";
    containers = {
      "mindwtr-cloud" = {
        image = "ghcr.io/dongdongbh/mindwtr-cloud:1.3.1";
        ports = [ "127.0.0.1:${toString cloudPort}:8787" ];
        volumes = [
          "/var/lib/mindwtr:/app/cloud_data"
        ];
        environment = {
          MINDWTR_CLOUD_CORS_ORIGIN = "https://${hostname}";
          MINDWTR_CLOUD_MAX_BODY_BYTES = "2000000";
          MINDWTR_CLOUD_MAX_ATTACHMENT_BYTES = "50000000";
        };
        environmentFiles = [
          config.vaultix.templates."mindwtr.env".path
        ];
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/mindwtr 0777 root root -"
  ];
}
