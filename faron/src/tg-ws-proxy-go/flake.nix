{
  description = "tg-ws-proxy-go dev environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f {
        inherit system;
        pkgs = import nixpkgs { inherit system; };
      });
    in
    {
      devShells = forAllSystems ({ system, pkgs }:
        pkgs.mkShell {
          packages = with pkgs; [ go gopls gotools ];
          shellHook = ''
            export GOTOOLCHAIN=local
            echo "tg-ws-proxy-go dev shell: $(go version)"
          '';
        });
    };
}