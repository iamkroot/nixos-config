{
  lib,
  inputs,
  myUtils,
  ...
}:
{
  imports = [
    (myUtils.mkCaddyModule "icons" {
      extraHostConfig = {
        extraConfig = lib.mkForce ''
          		  # Serve the SVG folder
          		  root * ${inputs.dashboard-icons}/svg
          		  file_server
          		  
          		  # Ensure CORS is allowed so dashboards don't get blocked
          		  header Access-Control-Allow-Origin "*"
          		  
          		  # Tell browsers to cache these heavily
          		  header Cache-Control "public, max-age=31536000"
          		'';
      };
    })
  ];

}
