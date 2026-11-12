#!/bin/bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: bash export-ps4-patches.sh [options]

Export the PS4 branch's downstream commits as an ordered patch series.
Create or reuse a bare clone, fetch the PS4 default HEAD, and read its
committed Makefile to fetch the corresponding official Linux release tag.

    --repo PATH          Repository/cache (default: ./linux.git beside script)
    --ps4-url URL        PS4 clone/fetch URL (default: GitLab rmuxnet/linux)
    --upstream-url URL   Release tag URL (default: kernel.org stable/linux)
    --ps4-ref REF        Use a local PS4 ref instead of fetching remote HEAD
    --base REF           Use a local baseline instead of fetching release tag
  --output PATH        New output directory (default: ./ps4-patches)
  -h, --help           Show this help

The initial clone needs full branch history and may be large. Later runs
reuse the cache. Fetches use private refs and do not overwrite local tags.
No checkout, reset, or changes to any worktree or index are performed.
Use --ps4-ref and --base together with an existing repo for offline export.
All downstream commits are included, not just commits mentioning PS4.
Merge commits are rejected because format-patch cannot preserve them.
EOF
}

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repository="$script_directory/linux.git"
ps4_url=https://gitlab.com/rmuxnet/linux.git
upstream_url=https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
ps4_ref=
base_ref=
output="$PWD/ps4-patches"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --repo|--ps4-url|--upstream-url|--ps4-ref|--base|--output)
            [[ $# -ge 2 && -n "$2" ]] || die "Missing value for $1"
            case "$1" in
                --repo) repository=$2 ;;
                --ps4-url) ps4_url=$2 ;;
                --upstream-url) upstream_url=$2 ;;
                --ps4-ref) ps4_ref=$2 ;;
                --base) base_ref=$2 ;;
                --output) output=$2 ;;
            esac
            shift 2
            ;;
        *) die "Unknown option: $1 (use --help)" ;;
    esac
done

[[ ! -e "$output" && ! -L "$output" ]] || die "Output already exists: $output"
if [[ ! -e "$repository" && ! -L "$repository" ]]; then
    git clone --bare --single-branch --no-tags -- "$ps4_url" "$repository"
fi
repository=$(cd -- "$repository" && pwd) || die "Cannot open repository"
git -C "$repository" rev-parse --git-dir >/dev/null
[[ $(git -C "$repository" rev-parse --is-shallow-repository) == false ]] ||
    die "Full history is required; unshallow the repository first"
if [[ -z "$ps4_ref" ]]; then
    ps4_ref=refs/ps4-export/source
    git -C "$repository" fetch --no-tags --no-write-fetch-head -- "$ps4_url" \
        "+HEAD:$ps4_ref"
fi
tip=$(git -C "$repository" rev-parse --verify --end-of-options "$ps4_ref^{commit}")

release_tag=
if [[ -n "$base_ref" ]]; then
    base=$(git -C "$repository" rev-parse --verify --end-of-options "$base_ref^{commit}")
else
    source_makefile=$(git -C "$repository" show "$tip:Makefile")
    release_version=$(printf '%s\n' "$source_makefile" | awk \
        '$1 == "VERSION" { version = $3 }
         $1 == "PATCHLEVEL" { patchlevel = $3 }
         $1 == "SUBLEVEL" { sublevel = $3 }
         $1 == "EXTRAVERSION" { extra = $3 }
         END {
             if (version !~ /^[0-9]+$/ || patchlevel !~ /^[0-9]+$/ ||
                 sublevel !~ /^[0-9]+$/) exit 1
             printf "%s.%s", version, patchlevel
             if (sublevel + 0 > 0) printf ".%s", sublevel
             printf "%s", extra
         }') || die "Cannot read kernel version from committed Makefile; specify --base"
    release_tag="v$release_version"
    upstream_ref="refs/ps4-export/upstream/$release_tag"
    git check-ref-format "$upstream_ref" || die "Invalid release tag; specify --base"
    if ! git -C "$repository" fetch --no-tags --no-write-fetch-head -- "$upstream_url" \
        "refs/tags/$release_tag:$upstream_ref"; then
        die "Cannot fetch official $release_tag; check --upstream-url or specify --base"
    fi
    base=$(git -C "$repository" rev-parse --verify "$upstream_ref^{commit}")
fi
git -C "$repository" merge-base --is-ancestor "$base" "$tip" ||
    die "Baseline is not an ancestor of the PS4 source"

range="$base..$tip"
count=$(git -C "$repository" rev-list --count "$range")
[[ "$count" -gt 0 ]] || die "No commits to export"
[[ $(git -C "$repository" rev-list --count --merges "$range") == 0 ]] ||
    die "Range contains merge commits; choose a linear PS4 history"
mkdir -- "$output"
output=$(cd -- "$output" && pwd)

git -C "$repository" -c format.useAutoBase=false format-patch \
    --quiet --always --no-cover-letter --numbered --no-numbered-files \
    --no-thread --no-attach --full-index --binary --no-renames \
    --no-signature --suffix=.patch --output-directory "$output" "$range"

patches=("$output"/*.patch)
[[ ${#patches[@]} -eq "$count" ]] || die "Patch count does not match commit count; inspect $output"
for patch in "${patches[@]}"; do
    printf '%s\n' "${patch##*/}"
done > "$output/series"
git -C "$repository" log --reverse --topo-order --format='%H %s' "$range" > "$output/commits.txt"
{
    printf 'PS4 URL: %s\n' "$ps4_url"
    printf 'PS4 ref: %s\nPS4 commit: %s\n' "$ps4_ref" "$tip"
    if [[ -n "$release_tag" ]]; then
        printf 'Upstream URL: %s\nRelease tag: %s\n' "$upstream_url" "$release_tag"
    else
        printf 'Explicit base ref: %s\n' "$base_ref"
    fi
    printf 'Base commit: %s\nPatch count: %s\n' "$base" "$count"
    printf '\nBase description: '
    git -C "$repository" show -s --format='%H %s' "$base"
    printf '\nPatches preserve commit authors and messages, including credit trailers.\n'
    printf 'This exports all downstream changes, including configuration and documentation.\n'
    printf 'Applying to a newer kernel may require manual porting and PS4 hardware testing.\n'
} > "$output/manifest.txt"

printf 'Exported %s patches to %s\nBase: %s\n' "$count" "$output" "$base"