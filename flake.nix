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
      llvm = pkgs.llvmPackages;
      clangHeaders = "${pkgs.lib.getLib llvm.clang-unwrapped}/lib/clang/${pkgs.lib.versions.major llvm.clang-unwrapped.version}/include";

      compatibilityDir = ./compatibility + "/${baseKernel.version}";
      adaptedPatches =
        if builtins.pathExists compatibilityDir then
          pkgs.applyPatches {
            name = "ps4-patches-${baseKernel.version}";
            src = ./ps4-patches;
            nativeBuildInputs = [ pkgs.git ];

            patchPhase = ''
              runHook prePatch
              while IFS= read -r patch; do
                echo "Applying compatibility patch $patch"
                git apply --whitespace=nowarn "${compatibilityDir}/$patch"
              done < ${compatibilityDir}/series
              runHook postPatch
            '';
          }
        else
          ./ps4-patches;

      patchedSource = pkgs.applyPatches {
        name = "linux-ps4-source-${baseKernel.version}";
        src = baseKernel.src;
        nativeBuildInputs = [ pkgs.git ];

        patchPhase = ''
          runHook prePatch
          while IFS= read -r patch; do
            echo "Applying $patch"
            git apply --allow-empty --whitespace=nowarn "${adaptedPatches}/$patch"
          done < ${adaptedPatches}/series
          runHook postPatch
        '';
      };

      mkKernel =
        {
          profile ? "General",
          lto ? "ThinLTO",
        }:
        let
          profileLower = pkgs.lib.toLower profile;
          ltoLower = pkgs.lib.toLower lto;
          pname =
            "linux-ps4"
            + pkgs.lib.optionalString (profileLower != "general") "-${profileLower}"
            + pkgs.lib.optionalString (ltoLower != "thinlto") "-${ltoLower}";
          drv = llvm.stdenv.mkDerivation rec {
            inherit pname;
            inherit (baseKernel) version;
            src = patchedSource;

            strictDeps = true;
            hardeningDisable = [ "all" ];
            dontConfigure = true;
            dontStrip = true;

            nativeBuildInputs = with pkgs; [
              llvm.llvm
              llvm.lld
              bc
              bison
              flex
              openssl
              pahole
              perl
              pkg-config
              python3Minimal
              zstd
            ];
            buildInputs = with pkgs; [
              elfutils
              openssl
              zlib
            ];

            postPatch = ''
              patchShebangs scripts
            '';

            KBUILD_BUILD_USER = "nix";
            KBUILD_BUILD_HOST = "nix";
            KBUILD_BUILD_VERSION = "1";

            # Kernel code must not inherit userspace flags from Nix's compiler wrapper.
            MAKEFLAGS = pkgs.lib.concatStringsSep " " [
              "CC=${llvm.clang-unwrapped}/bin/clang"
              "HOSTCC=${llvm.clang}/bin/clang"
              "HOSTCXX=${llvm.clang}/bin/clang++"
              "HOSTLDFLAGS=--ld-path=${llvm.stdenv.cc.bintools}/bin/ld"
              "LD=${llvm.lld}/bin/ld.lld"
              "CFLAGS_KERNEL=-I${clangHeaders}"
              "CFLAGS_MODULE=-I${clangHeaders}"
            ];

            buildPhase = ''
              runHook preBuild
              export KBUILD_BUILD_TIMESTAMP="@$SOURCE_DATE_EPOCH"
              bash ./build.sh --option 1 use=${profile} lto=${lto} mode=Release jobs="$NIX_BUILD_CORES"
              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              install -Dm644 out/bzImage "$out/bzImage"
              install -Dm644 out/.config "$out/config"
              install -Dm644 System.map "$out/System.map"
              install -Dm644 include/config/kernel.release "$out/kernel.release"
              runHook postInstall
            '';

            passthru = rec {
              inherit (baseKernel)
                version
                moduleBuildDependencies
                commonMakeFlags
                modules
                ;
              modDirVersion = baseKernel.modDirVersion or version;
              target = "bzImage";
              features = {
                efiBootStub = true;
                ia32Emulation = true;
                netfilterRPFilter = true;
              };
              buildDTBs = false;
              configfile = "${drv}/config";
              config = {
                isSet = attr: false;
                getValue = attr: null;
                isYes = attr: false;
                isNo = attr: false;
                isModule = attr: false;
                isEnabled = attr: false;
                isDisabled = attr: true;
              };
              override =
                newArgs:
                let
                  origArgs = {
                    inherit features;
                    kernelPatches = [ ];
                  };
                  args = if builtins.isFunction newArgs then newArgs origArgs else newArgs;
                in
                drv
                // {
                  features = pkgs.lib.recursiveUpdate features (args.features or { });
                };
              isLTS = false;
              isZen = false;
              kernelOlder = pkgs.lib.versionOlder version;
              kernelAtLeast = pkgs.lib.versionAtLeast version;
              dev = baseKernel.dev;
            };

            meta = {
              description = "Strawberry Linux kernel image for PS4 (${profile} profile, ${lto})";
              homepage = "https://gitlab.com/rmuxnet/linux";
              platforms = [ system ];
            };
          };
        in
        drv;

      mkKernelPackages =
        kernel:
        (pkgs.linuxPackagesFor kernel).extend (
          self: super: {
            inherit (kernel)
              type
              name
              drvPath
              outPath
              outputName
              meta
              ;
          }
        );

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

      nixosModules = rec {
        default =
          { config, lib, pkgs, ... }:
          let
            cfg = config.hardware.ps4.kernel;
            profileLower = lib.toLower cfg.profile;
            ltoLower = lib.toLower cfg.lto;
            pkgKey = "linuxPackages-ps4-${profileLower}-${ltoLower}";
          in
          {
            options.hardware.ps4.kernel = {
              profile = lib.mkOption {
                type = lib.types.enum [
                  "General"
                  "Server"
                  "SlopMax"
                  "Slopium"
                ];
                default = "General";
                description = "Strawberry PS4 Linux kernel profile.";
              };
              lto = lib.mkOption {
                type = lib.types.enum [
                  "ThinLTO"
                  "FullLTO"
                ];
                default = "ThinLTO";
                description = "Link-time optimization flavor.";
              };
            };

            config = {
              boot.kernelPackages = self.packages.${pkgs.stdenv.system}.${pkgKey};
            };
          };

        general = default;
        server =
          { ... }:
          {
            imports = [ default ];
            hardware.ps4.kernel.profile = "Server";
          };
        slopmax =
          { ... }:
          {
            imports = [ default ];
            hardware.ps4.kernel.profile = "SlopMax";
          };
        slopium =
          { ... }:
          {
            imports = [ default ];
            hardware.ps4.kernel.profile = "Slopium";
          };
      };

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
