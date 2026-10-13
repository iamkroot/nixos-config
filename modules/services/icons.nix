{
  myUtils,
  ...
}:
{
  imports = [
    (myUtils.mkCaddyModule "icons" {
      extraHostConfig = {
        extraConfig = ''
          root * ${./icons/custom}

          # 1. Serve local custom overrides if they exist
          @file_exists file
          handle @file_exists {
            file_server
          }

          # 2. Format-aware on-demand proxy to Homarr upstream CDN with negative caching
          handle {
            @png path *.png
            rewrite @png /gh/homarr-labs/dashboard-icons/png{uri}

            @webp path *.webp
            rewrite @webp /gh/homarr-labs/dashboard-icons/webp{uri}

            @svg not path *.png *.webp
            rewrite @svg /gh/homarr-labs/dashboard-icons/svg{uri}

            reverse_proxy https://cdn.jsdelivr.net {
              header_up Host cdn.jsdelivr.net

              @notFound status 404
              handle_response @notFound {
                header Cache-Control "public, max-age=86400"
                respond "Icon not found" 404
              }
            }
          }

          header Access-Control-Allow-Origin "*"
          header Cache-Control "public, max-age=31536000, immutable"
        '';
      };
    })
  ];
  infra.services.catalog.icons.enable = false;
}
