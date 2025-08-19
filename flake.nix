{
  inputs.flakelight.url = "github:nix-community/flakelight";
  inputs.nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-25.05";

  outputs = inputs: inputs.flakelight ./. {
    inherit inputs;

    devShell.packages = pkgs: with pkgs; [
      awscli2
      opentofu
    ];
  };
}
