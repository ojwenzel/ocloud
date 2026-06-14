{
  description = "ocloud — Hetzner VPS NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    disko = {
      url = "github:nix-community/disko/latest";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, disko, sops-nix, ... }: {
    nixosConfigurations.ocloud = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        disko.nixosModules.disko
        sops-nix.nixosModules.sops
        ./hosts/ocloud/configuration.nix
        ./hosts/ocloud/disk-config.nix
      ];
    };
  };
}
