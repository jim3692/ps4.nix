{
  pkgs,
  baseKernel,
  patchedSource,
}:
let
  llvm = pkgs.llvmPackages;
  clangHeaders = "${pkgs.lib.getLib llvm.clang-unwrapped}/lib/clang/${pkgs.lib.versions.major llvm.clang-unwrapped.version}/include";

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
          platforms = [ pkgs.stdenv.system ];
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
in
{
  inherit mkKernel mkKernelPackages;
}
