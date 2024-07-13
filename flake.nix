{
  description = "Zig dev environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.zig.url = "github:mitchellh/zig-overlay";

  outputs = { nixpkgs, flake-utils, zig, ... }:
  flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      devShells.default = with pkgs; mkShell {
        packages = [ 
          bashInteractive 
          zig.packages.${system}.master
        ];
      };
    });
}
