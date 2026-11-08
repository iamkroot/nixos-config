{ pkgs }:
pkgs.writeShellApplication {
  name = "arr-import-extras";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.util-linux
    pkgs.fd
    pkgs.bash
  ];
  text = builtins.readFile ./arr-import-extras.sh;
}
