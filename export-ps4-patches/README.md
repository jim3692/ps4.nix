# PS4 kernel patch export

Run from this directory:

```sh
bash ./export-ps4-patches.sh
```

On the first run, this creates `linux.git/`, a bare clone of
`https://gitlab.com/rmuxnet/linux.git`, beside the script. It fetches the
remote's default `HEAD`, reads that commit's Makefile version, and fetches
the corresponding release tag from the official Linux stable repository.
It then exports downstream commits to `ps4-patches/` in the current directory.

Later runs reuse the bare cache and refresh the source and release refs.
The initial clone needs full branch history, so allow substantial time and
disk space. No checkout is created. The existing `linux/` directory is not
used or changed. The output directory must not already exist; choose a new
`--output` for another export.

The output contains numbered mail patches, an ordered `series` file,
`commits.txt`, and `manifest.txt` with the exact source and baseline commits.
Commit authors, messages, and credit trailers are preserved. Configuration,
firmware, build, and documentation changes are included, not just commits
whose subjects mention PS4.
The manifest excludes the local cache path, so exporting the same source
and baseline from different cache directories produces identical output.

The parent project commits its generated series in `../ps4-patches/`. Its
[scheduled workflow](../.github/workflows/update-ps4-patches.yml) exports into
a fresh temporary directory and replaces the committed series only in the
runner's checkout. It pushes an update only after patch application and the
ThinLTO kernel build pass. It never advances the nixpkgs pin automatically.

## Baseline selection

The committed Makefile's `VERSION`, `PATCHLEVEL`, `SUBLEVEL`, and
`EXTRAVERSION` determine the release tag: for example, `v7.3.3`, `v7.3`
for sublevel zero, or `v7.3-rc1`. The official tag is fetched into
`refs/ps4-export/upstream/<tag>`, separate from any PS4 tags with the same
name. The PS4 default HEAD is stored at `refs/ps4-export/source`.

The release must be an ancestor of the PS4 source. Missing release tags,
shallow history, and merge commits are rejected rather than guessed or
silently omitted. Review the manifest and commit list before porting.

For the current PS4 branch, the baseline is
`d50d994bffa3c7c6db2d8bc4c5f0c55e3f46b0cd` (`Linux 7.3.3`), yielding
124 downstream commits. The repository's `v7.3.3` tag already includes PS4
changes and is not the upstream release baseline. Using only the common
ancestor with mainline would also export 592 inherited stable commits.

Change the clone location or source URLs:

```sh
bash ./export-ps4-patches.sh \
  --repo ./ps4-cache.git \
  --ps4-url https://gitlab.com/rmuxnet/linux.git \
  --upstream-url https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git \
  --output ./ps4-7.3.3-patches
```

For offline export from the existing repository, specify both local refs:

```sh
bash ./export-ps4-patches.sh \
  --repo ./linux \
  --ps4-ref origin/ps4/7.3.3 \
  --base d50d994bffa3c7c6db2d8bc4c5f0c55e3f46b0cd \
  --output ./ps4-offline-patches
```

An existing regular repository is also accepted. Fetches only target private
export refs; its worktree, index, local branches, and local tags are not
changed. Supplying both `--ps4-ref` and `--base` avoids fetches entirely.

## Porting to a newer kernel

After the default export, fetch newer mainline into the cache, create a
separate worktree, and apply the series:

```sh
git -C linux.git fetch --no-tags \
  https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git \
  refs/heads/master:refs/ps4-export/mainline
git -C linux.git worktree add -b ps4/port ../linux-ps4-next refs/ps4-export/mainline
git -C linux-ps4-next am --3way --empty=keep "$PWD"/ps4-patches/*.patch
```

The shared repository supplies the original blobs for three-way merges.
On conflicts, resolve the files, stage them in the new worktree, and run
`git -C linux-ps4-next am --continue`. To abandon the application, run
`git -C linux-ps4-next am --abort`.

Exporting is not automatic forward-porting: API changes, already-applied
fixes, and build/configuration changes may need manual work. No newer-kernel
build or PS4 hardware compatibility is claimed. After porting, follow the
kernel tree's build documentation and test on the actual console.

## Tests

Run the local fixture suite without network access or a kernel clone:

```sh
bash ./tests/export-ps4-patches.sh
```