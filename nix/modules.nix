{ self }:
rec {
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
}
