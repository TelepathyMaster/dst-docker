#!/usr/bin/env bash
set -Eeuo pipefail
# Only called in the serialized publish job, after Docker Hub login.
version=${1:?Usage: release-tags.sh X.Y.Z namespace/repository commit}
repository=${2:?Missing Docker Hub repository}
commit=${3:?Missing commit}
[[ $version =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || { echo 'Stable X.Y.Z required' >&2; exit 1; }
[[ $repository =~ ^[a-z0-9_-]+/[a-z0-9_-]+$ ]] || { echo 'Expected namespace/repository' >&2; exit 1; }
[[ $commit =~ ^[a-f0-9]{40}$ ]] || { echo 'Full commit SHA required' >&2; exit 1; }
metadata=$(curl --fail --silent --show-error --retry 3 "https://hub.docker.com/v2/repositories/$repository/")
jq -e '.is_private == false' <<<"$metadata" >/dev/null || { echo 'Create a public Docker Hub repository before publishing' >&2; exit 1; }
all_tags=()
url="https://hub.docker.com/v2/repositories/$repository/tags/?page_size=100"
while [[ -n $url ]]; do
    [[ $url == "https://hub.docker.com/v2/repositories/$repository/tags/"* ]] || { echo 'Unexpected pagination URL' >&2; exit 1; }
    page=$(curl --fail --silent --show-error --retry 3 "$url")
    jq -e '.results | type == "array"' <<<"$page" >/dev/null
    mapfile -t page_tags < <(jq -r '.results[].name' <<<"$page")
    all_tags+=("${page_tags[@]}")
    url=$(jq -r '.next // empty' <<<"$page")
done
for tag in "${all_tags[@]}"; do
    [[ $tag != "$version" && $tag != "sha-$commit" ]] || { echo "Refusing to overwrite immutable tag $tag" >&2; exit 1; }
done
highest=$version
for tag in "${all_tags[@]}"; do
    if [[ $tag =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
        highest=$(printf '%s\n%s\n' "$highest" "$tag" | sort -V | tail -n 1)
    fi
done
printf 'version=%s\nlatest=%s\n' "$version" "$([[ $highest == "$version" ]] && echo true || echo false)"
