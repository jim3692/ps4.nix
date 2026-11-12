# PS4 kernel flake

Build the [Strawberry PS4 Linux kernel](https://gitlab.com/rmuxnet/linux)
by applying the committed [PS4 patch series](ps4-patches/series) to
`nixpkgs.linuxPackages_latest.kernel.src`. No submodules are needed.
This project packages upstream's work; patch authors, commit messages, and
credit trailers are preserved.

## Build

Use an x86_64 Linux machine with Nix and the `nix-command`
and `flakes` experimental features enabled.

```sh
nix build .#linux-ps4
```

`nix build` builds the same default package. Use Git-backed flake references
so untracked files, including ignored caches and local kernel checkouts, are
not copied into the Nix store. Add new build inputs to Git before running Nix:

```sh
git add flake.nix flake.lock ps4-patches
```

Edits to tracked files are included without committing them. Ignoring a file
does not exclude it if it is already tracked.

Choose an explicit LTO variant with:

```sh
nix build .#linux-ps4-thinlto
nix build .#linux-ps4-fulllto
```

`default` and `linux-ps4` remain aliases for `linux-ps4-thinlto`.
FullLTO generally requires more RAM and longer linking than ThinLTO, without
guaranteeing better runtime performance.

Both variants use upstream's General / Release profile, Clang/LLVM,
and bundled firmware included in the exported binary patches. The build does
not fetch firmware during compilation or apply CachyOS patches.
The firmware retains its upstream licensing; see
[the firmware licensing notes](https://gitlab.com/rmuxnet/linux/-/blob/ps4/7.3.3/extra_firmware/README.license).
This preserves upstream's configuration, including its disabled hardening options.

Kernel compilation needs substantial RAM and disk space. Limit parallelism
when necessary:

```sh
nix build .#linux-ps4 --cores 4 --max-jobs 1
```

The result contains:

- `result/bzImage`: the PS4 kernel image.
- `result/config`: the effective kernel configuration.
- `result/System.map`: kernel symbols.
- `result/kernel.release`: the full kernel release string.

Copy `result/bzImage` to your boot media alongside a compatible initramfs,
following [upstream's installation instructions](https://gitlab.com/rmuxnet/linux#install).
The loader and initramfs are not built by this flake. This is a standalone
kernel image, not a NixOS `boot.kernelPackages` package or a modules/headers
distribution. A successful build does not verify booting on PS4 hardware.

## Updates

The [patch manifest](ps4-patches/manifest.txt) records the exact PS4 source
and official Linux baseline commits. The nixpkgs input is pinned to a revision
whose `linuxPackages_latest.kernel` is 7.3.3, matching the current patch
baseline. Kernel version and source are taken from nixpkgs rather than
hard-coded in the builder. [flake.lock](flake.lock) pins the input contents.

The [update workflow](.github/workflows/update-ps4-patches.yml) runs daily at
03:17 UTC and can also be started manually. It:

1. Reuses a cached bare repository and exports the PS4 default branch.
2. Replaces only the generated patch directory, including removing stale patches.
3. If patches changed, checks their ordered application and builds ThinLTO
   (including configuration).
4. Commits and pushes the generated files only after validation succeeds.

Failures leave the previously committed patches unchanged. Unchanged exports
produce no commit. FullLTO is available but is not built by the update job.
The workflow needs permission to push to the default branch; branch protection
must allow the automation. No GitHub workflow has been run locally.

Automatic export is not automatic forward-porting: the original 7.3.3 series
does not apply cleanly to 7.3.4. The workflow deliberately does not update
nixpkgs. When moving to a new kernel baseline, select a compatible nixpkgs
revision in [flake.nix](flake.nix), run `nix flake update nixpkgs`, regenerate
the patches, and validate both variants as needed.

For manual export, see [the exporter documentation](export-ps4-patches/README.md).
The exporter requires a new output directory; review and replace
[ps4-patches/](ps4-patches/) only after a successful export. Check patch
application without compiling the kernel using `nix flake check`.
