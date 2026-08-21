{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  packages = with pkgs; [
    go
    gopls
    gotools
  ];

  shellHook = ''
    export GOTOOLCHAIN=local
    echo "tg-ws-proxy-go dev shell: $(go version)"
  '';
}