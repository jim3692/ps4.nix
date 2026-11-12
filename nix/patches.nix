{
  pkgs,
  baseKernel,
  ps4PatchesDir ? ../ps4-patches,
  compatibilityDir ? ../compatibility,
}:
let
  versionCompatibilityDir = compatibilityDir + "/${baseKernel.version}";

  adaptedPatches =
    if builtins.pathExists versionCompatibilityDir then
      pkgs.applyPatches {
        name = "ps4-patches-${baseKernel.version}";
        src = ps4PatchesDir;
        nativeBuildInputs = [ pkgs.git ];

        patchPhase = ''
          runHook prePatch
          while IFS= read -r patch; do
            echo "Applying compatibility patch $patch"
            git apply --whitespace=nowarn "${versionCompatibilityDir}/$patch"
          done < ${versionCompatibilityDir}/series
          runHook postPatch
        '';
      }
    else
      ps4PatchesDir;

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
in
{
  inherit adaptedPatches patchedSource;
}
