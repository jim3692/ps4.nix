{
  description = "Strawberry PS4 Linux kernel";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable-small";
  };

  outputs =
    { self, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      baseKernel = pkgs.linuxPackages_latest.kernel;

      inherit (import ./nix/patches.nix { inherit pkgs baseKernel; })
        patchedSource
        ;

      inherit (import ./nix/kernel.nix { inherit pkgs baseKernel patchedSource; })
        mkKernel
        mkKernelPackages
        ;

      # Profile definitions (General, Server, SlopMax, Slopium)
      linux-ps4-general-thinlto = mkKernel {
        profile = "General";
        lto = "ThinLTO";
      };
      linux-ps4-general-fulllto = mkKernel {
        profile = "General";
        lto = "FullLTO";
      };
      linux-ps4-server-thinlto = mkKernel {
        profile = "Server";
        lto = "ThinLTO";
      };
      linux-ps4-server-fulllto = mkKernel {
        profile = "Server";
        lto = "FullLTO";
      };
      linux-ps4-slopmax-thinlto = mkKernel {
        profile = "SlopMax";
        lto = "ThinLTO";
      };
      linux-ps4-slopmax-fulllto = mkKernel {
        profile = "SlopMax";
        lto = "FullLTO";
      };
      linux-ps4-slopium-thinlto = mkKernel {
        profile = "Slopium";
        lto = "ThinLTO";
      };
      linux-ps4-slopium-fulllto = mkKernel {
        profile = "Slopium";
        lto = "FullLTO";
      };

      linuxPackages-ps4-general-thinlto = mkKernelPackages linux-ps4-general-thinlto;
      linuxPackages-ps4-general-fulllto = mkKernelPackages linux-ps4-general-fulllto;
      linuxPackages-ps4-server-thinlto = mkKernelPackages linux-ps4-server-thinlto;
      linuxPackages-ps4-server-fulllto = mkKernelPackages linux-ps4-server-fulllto;
      linuxPackages-ps4-slopmax-thinlto = mkKernelPackages linux-ps4-slopmax-thinlto;
      linuxPackages-ps4-slopmax-fulllto = mkKernelPackages linux-ps4-slopmax-fulllto;
      linuxPackages-ps4-slopium-thinlto = mkKernelPackages linux-ps4-slopium-thinlto;
      linuxPackages-ps4-slopium-fulllto = mkKernelPackages linux-ps4-slopium-fulllto;
    in
    {
      checks.${system}.patches = patchedSource;

      packages.${system} = rec {
        default = linuxPackages-ps4;

        # General
        linux-ps4-general = linux-ps4-general-thinlto;
        linuxPackages-ps4-general = linuxPackages-ps4-general-thinlto;
        linux-ps4 = linux-ps4-general;
        linuxPackages-ps4 = linuxPackages-ps4-general;
        linux-ps4-thinlto = linux-ps4-general-thinlto;
        linux-ps4-fulllto = linux-ps4-general-fulllto;
        linuxPackages-ps4-thinlto = linuxPackages-ps4-general-thinlto;
        linuxPackages-ps4-fulllto = linuxPackages-ps4-general-fulllto;
        linux_ps4 = linux-ps4;
        linuxPackages_ps4 = linuxPackages-ps4;

        # Server
        linux-ps4-server = linux-ps4-server-thinlto;
        linuxPackages-ps4-server = linuxPackages-ps4-server-thinlto;

        # SlopMax
        linux-ps4-slopmax = linux-ps4-slopmax-thinlto;
        linuxPackages-ps4-slopmax = linuxPackages-ps4-slopmax-thinlto;

        # Slopium
        linux-ps4-slopium = linux-ps4-slopium-thinlto;
        linuxPackages-ps4-slopium = linuxPackages-ps4-slopium-thinlto;

        # Explicit flavour derivations & package sets
        inherit
          linux-ps4-general-thinlto
          linux-ps4-general-fulllto
          linux-ps4-server-thinlto
          linux-ps4-server-fulllto
          linux-ps4-slopmax-thinlto
          linux-ps4-slopmax-fulllto
          linux-ps4-slopium-thinlto
          linux-ps4-slopium-fulllto
          linuxPackages-ps4-general-thinlto
          linuxPackages-ps4-general-fulllto
          linuxPackages-ps4-server-thinlto
          linuxPackages-ps4-server-fulllto
          linuxPackages-ps4-slopmax-thinlto
          linuxPackages-ps4-slopmax-fulllto
          linuxPackages-ps4-slopium-thinlto
          linuxPackages-ps4-slopium-fulllto
          ;
      };

      nixosModules = import ./nix/modules.nix { inherit self; };

      overlays.default = final: prev: {
        linux-ps4 = self.packages.${final.stdenv.system}.linux-ps4;
        linuxPackages-ps4 = self.packages.${final.stdenv.system}.linuxPackages-ps4;
        linux-ps4-server = self.packages.${final.stdenv.system}.linux-ps4-server;
        linuxPackages-ps4-server = self.packages.${final.stdenv.system}.linuxPackages-ps4-server;
        linux-ps4-slopmax = self.packages.${final.stdenv.system}.linux-ps4-slopmax;
        linuxPackages-ps4-slopmax = self.packages.${final.stdenv.system}.linuxPackages-ps4-slopmax;
        linux-ps4-slopium = self.packages.${final.stdenv.system}.linux-ps4-slopium;
        linuxPackages-ps4-slopium = self.packages.${final.stdenv.system}.linuxPackages-ps4-slopium;
      };
    };
}
