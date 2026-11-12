#!/bin/bash
set -euo pipefail

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
exporter="$script_directory/export-ps4-patches.sh"
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/ps4-export-test.XXXXXX")
trap 'rm -rf -- "$test_directory"' EXIT
upstream="$test_directory/upstream.git"
source_repository="$test_directory/ps4.git"
cache="$test_directory/cache.git"

fixture_commit() {
    local repository=$1 parent=$2 sublevel=$3 extra=$4 content=$5
    local makefile_blob content_blob tree
    local parent_arguments=()
    if [[ -n "$parent" ]]; then
        parent_arguments=(-p "$parent")
    fi
    makefile_blob=$(printf 'VERSION = 7\nPATCHLEVEL = 3\nSUBLEVEL = %s\nEXTRAVERSION = %s\n' \
        "$sublevel" "$extra" | git -C "$repository" hash-object -w --stdin)
    content_blob=$(printf '%s\n' "$content" | git -C "$repository" hash-object -w --stdin)
    tree=$(printf '100644 blob %s\tMakefile\n100644 blob %s\tfixture.txt\n' \
        "$makefile_blob" "$content_blob" | git -C "$repository" mktree)
    git -C "$repository" -c user.name='Export Test' -c user.email=test@example.com \
        commit-tree "$tree" ${parent_arguments[@]+"${parent_arguments[@]}"} -m "$content"
}

run_export() {
    bash "$exporter" --repo "$cache" --ps4-url "$source_repository" \
        --upstream-url "$upstream" --output "$1"
}

git init --bare --quiet "$upstream"
git init --bare --quiet "$source_repository"
base=$(fixture_commit "$upstream" '' 3 '' baseline)
git -C "$upstream" -c user.name='Export Test' -c user.email=test@example.com \
    tag -a v7.3.3 -m 'Official fixture release' "$base"
git -C "$source_repository" fetch --quiet --no-tags "$upstream" refs/tags/v7.3.3
tip=$(fixture_commit "$source_repository" "$base" 3 '' downstream-one)
git -C "$source_repository" update-ref refs/heads/ps4/custom-default "$tip"
git -C "$source_repository" symbolic-ref HEAD refs/heads/ps4/custom-default
git -C "$source_repository" update-ref refs/tags/v7.3.3 "$tip"

run_export "$test_directory/first output"
[[ $(git -C "$cache" rev-parse --is-bare-repository) == true ]]
[[ $(git -C "$cache" rev-parse 'refs/ps4-export/upstream/v7.3.3^{commit}') == "$base" ]]
[[ $(wc -l < "$test_directory/first output/series") -eq 1 ]]

git -C "$cache" update-ref refs/tags/v7.3.3 "$tip"
next_tip=$(fixture_commit "$source_repository" "$tip" 3 '' downstream-two)
git -C "$source_repository" update-ref refs/heads/ps4/custom-default "$next_tip"
run_export "$test_directory/second"
[[ $(git -C "$cache" rev-parse refs/ps4-export/source) == "$next_tip" ]]
[[ $(git -C "$cache" rev-parse refs/tags/v7.3.3) == "$tip" ]]
[[ $(wc -l < "$test_directory/second/series") -eq 2 ]]

(
    cache="$test_directory/another-cache.git"
    run_export "$test_directory/repeated"
)
diff -r "$test_directory/second" "$test_directory/repeated"

GIT_INDEX_FILE="$test_directory/index" git -C "$cache" read-tree "$base"
while IFS= read -r patch_name; do
    GIT_INDEX_FILE="$test_directory/index" git -C "$cache" apply --cached \
        "$test_directory/second/$patch_name"
done < "$test_directory/second/series"
[[ $(GIT_INDEX_FILE="$test_directory/index" git -C "$cache" write-tree) == \
    $(git -C "$cache" rev-parse "$next_tip^{tree}") ]]

bash "$exporter" --repo "$cache" --ps4-ref "$next_tip" --base "$base" \
    --ps4-url "$test_directory/nonexistent" --upstream-url "$test_directory/nonexistent" \
    --output "$test_directory/offline"
[[ $(wc -l < "$test_directory/offline/series") -eq 2 ]]

for extra in '' -rc1; do
    release_base=$(fixture_commit "$source_repository" '' 0 "$extra" "release$extra")
    git -C "$source_repository" update-ref refs/heads/release "$release_base"
    git -C "$upstream" fetch --quiet --no-tags "$source_repository" refs/heads/release
    git -C "$upstream" update-ref "refs/tags/v7.3$extra" "$release_base"
    release_tip=$(fixture_commit "$source_repository" "$release_base" 0 "$extra" "ps4$extra")
    git -C "$source_repository" update-ref refs/heads/ps4/custom-default "$release_tip"
    run_export "$test_directory/release$extra"
    [[ $(git -C "$cache" rev-parse "refs/ps4-export/upstream/v7.3$extra") == "$release_base" ]]
done

missing_tip=$(fixture_commit "$source_repository" "$next_tip" 4 '' missing-release)
git -C "$source_repository" update-ref refs/heads/ps4/custom-default "$missing_tip"
if run_export "$test_directory/missing" > "$test_directory/missing.log" 2>&1; then
    printf 'FAIL: missing official release tag was accepted\n' >&2
    exit 1
fi
[[ ! -e "$test_directory/missing" ]]

if run_export "$test_directory/second" > "$test_directory/existing.log" 2>&1; then
    printf 'FAIL: existing output directory was accepted\n' >&2
    exit 1
fi
printf 'PASS: bare clone, reuse, reproducibility, default HEAD, tag isolation, replay, offline refs, release versions, and errors\n'