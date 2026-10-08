#!/usr/bin/env bash
set -Eeuo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT
mkdir "$test_root/bin"
export PATH="$test_root/bin:$PATH"
cat >"$test_root/bin/curl" <<'MOCK'
#!/usr/bin/env bash
case "${*: -1}" in
    */tags/*) if [[ -n ${MOCK_TAGS:-} ]]; then printf '%s\n' "$MOCK_TAGS"; else printf '%s\n' '{"results":[],"next":null}'; fi ;;
    *) printf '%s\n' '{"is_private":false}' ;;
esac
MOCK
chmod +x "$test_root/bin/curl"
commit=1234567890123456789012345678901234567890
release="$repo/scripts/release-tags.sh"
expect_failure() {
    if "$@" >"$test_root/output" 2>&1; then echo 'Expected release rejection' >&2; exit 1; fi
}
"$release" 1.0.0 user/dst "$commit" >"$test_root/output"
rg -q '^latest=true$' "$test_root/output"
export MOCK_TAGS='{"results":[{"name":"2.0.0"},{"name":"latest"}],"next":null}'
"$release" 1.9.0 user/dst "$commit" >"$test_root/output"
rg -q '^latest=false$' "$test_root/output"
"$release" 10.0.0 user/dst "$commit" >"$test_root/output"
rg -q '^latest=true$' "$test_root/output"
expect_failure "$release" 2.0.0 user/dst "$commit"
expect_failure "$release" 01.0.0 user/dst "$commit"
expect_failure "$release" 1.0.0-rc1 user/dst "$commit"
export MOCK_TAGS='{"results":[{"name":"sha-1234567890123456789012345678901234567890"}],"next":null}'
expect_failure "$release" 3.0.0 user/dst "$commit"
export MOCK_TAGS='{"results":[],"next":"https://unexpected.example/tags"}'
expect_failure "$release" 3.0.0 user/dst "$commit"
printf 'PASS release version ordering, immutable tags, SHA, validation and pagination guard\n'
