{
  description = "Strawberry PS4 Linux kernel";

  inputs = {
    # Keep linuxPackages_latest on the release targeted by the exported patches.
    nixpkgs.url = "github:NixOS/nixpkgs/41691813c5b74a5f1394fcac9a4dafa58b9e06f0";
  };

  outputs =
    { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      baseKernel = pkgs.linuxPackages_latest.kernel;
      llvm = pkgs.llvmPackages;
      clangHeaders = "${pkgs.lib.getLib llvm.clang-unwrapped}/lib/clang/${pkgs.lib.versions.major llvm.clang-unwrapped.version}/include";

      patchedSource = pkgs.applyPatches {
        name = "linux-ps4-source-${baseKernel.version}";
        src = baseKernel.src;
        nativeBuildInputs = [ pkgs.git ];

        patchPhase = ''
          runHook prePatch
          while IFS= read -r patch; do
            echo "Applying $patch"
            git apply --allow-empty --whitespace=nowarn "${./ps4-patches}/$patch"
          done < ${./ps4-patches}/series
          runHook postPatch
        '';
      };

      mkKernel = lto: llvm.stdenv.mkDerivation {
        pname = "linux-ps4";
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
          bash ./build.sh --option 1 use=General lto=${lto} mode=Release jobs="$NIX_BUILD_CORES"
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

        meta = {
          description = "Strawberry Linux kernel image for PS4 (Aeolia, Belize and Baikal)";
          homepage = "https://gitlab.com/rmuxnet/linux";
          platforms = [ system ];
        };
      };
    in
    {
      checks.${system}.patches = patchedSource;

      packages.${system} = rec {
        default = linux-ps4-thinlto;
        linux-ps4 = linux-ps4-thinlto;
        linux-ps4-thinlto = mkKernel "ThinLTO";
        linux-ps4-fulllto = mkKernel "FullLTO";
      };
    };
}
