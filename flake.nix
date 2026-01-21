{
  description = "QEMU images with pinned OVMF";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      packages.${system}.ovmf = pkgs.OVMF.fd;

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          pkgs.qemu
          pkgs.just
          pkgs.fd
          pkgs.ripgrep
        ];

        shellHook = ''
          export OVMF_DIR=${self.packages.${system}.ovmf}
        '';
      };
    };
}

