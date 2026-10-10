#!/usr/bin/env bash
set -Eeuo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
runner=
cleanup() {
    if [[ -n $runner ]]; then kill -TERM "$runner" 2>/dev/null || true; wait "$runner" 2>/dev/null || true; fi
    rm -rf "$test_root"
}
trap cleanup EXIT
export DST_ROOT="$test_root/game" DATA_ROOT="$test_root/data" MODS_SETUP="$test_root/mods.lua"
export STEAMCMD_BOOTSTRAP="$test_root/bootstrap" CLUSTER_NAME=Cluster_1 SHARD=Master
export TEST_ROOT="$test_root"
mkdir -p "$STEAMCMD_BOOTSTRAP" "$DATA_ROOT/DoNotStarveTogether/Cluster_1/Master"
cp "$repo/examples/cluster/cluster.ini" "$DATA_ROOT/DoNotStarveTogether/Cluster_1/"
cp "$repo/examples/cluster/Master/server.ini" "$DATA_ROOT/DoNotStarveTogether/Cluster_1/Master/"
printf 'test-only-token\n' >"$DATA_ROOT/DoNotStarveTogether/Cluster_1/cluster_token.txt"
printf 'ServerModSetup("123456")\n' >"$MODS_SETUP"
cat >"$test_root/fake-game" <<'MOCK'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$@" >"$TEST_ROOT/game-args"
touch "$TEST_ROOT/game-ready"
trap 'echo unexpected-term >>"$TEST_ROOT/game-signals"; exit 99' TERM INT
while IFS= read -r command; do
    if [[ $command == 'c_shutdown()' ]]; then
        # Model DST waiting for its console reader to observe EOF on shutdown.
        while IFS= read -r ignored; do :; done
        printf 'saved\n' >"$TEST_ROOT/saved"
        exit "${MOCK_GAME_EXIT:-0}"
    fi
done
exit 98
MOCK
chmod +x "$test_root/fake-game"
cat >"$STEAMCMD_BOOTSTRAP/steamcmd.sh" <<'MOCK'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$@" >"$TEST_ROOT/update-args"
if [[ ${MOCK_BLOCK:-0} == 1 ]]; then
    trap 'echo stopped >"$TEST_ROOT/update-stopped"; exit 143' TERM
    sleep 100 &
    printf '%s\n' "$!" >"$TEST_ROOT/update-child"
    touch "$TEST_ROOT/update-ready"
    wait "$!"
fi
if [[ ${MOCK_FAIL:-0} == 1 ]]; then exit 42; fi
mkdir -p "$DST_ROOT/bin64" "$DST_ROOT/steamapps"
cp "$TEST_ROOT/fake-game" "$DST_ROOT/bin64/dontstarve_dedicated_server_nullrenderer_x64"
cat >"$DST_ROOT/steamapps/appmanifest_343050.acf" <<MANIFEST
"AppState"
{
    "appid" "343050"
    "StateFlags" "${MOCK_STATE:-4}"
    "buildid" "12345"
}
MANIFEST
MOCK
chmod +x "$STEAMCMD_BOOTSTRAP/steamcmd.sh"
entry="$repo/scripts/entrypoint.sh"
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1" >&2; exit 1; }
expect_failure() {
    if "$@" >"$test_root/failure-log" 2>&1; then fail "Unexpected success: $*"; fi
}
await_file() {
    local count
    for (( count=0; count<100; count++ )); do [[ ! -f $1 ]] || return 0; sleep 0.05; done
    fail "Timed out waiting for $1"
}
finish_runner() {
    local expected=$1 status=0
    wait "$runner" || status=$?
    runner=
    [[ $status == "$expected" ]] || fail "Exit $status, expected $expected"
}

expect_failure "$entry" unknown
expect_failure "$entry" run --validate
expect_failure env CLUSTER_NAME=../bad "$entry" update
expect_failure env SHARD=Other "$entry" update
expect_failure "$entry" run
pass 'command validation and missing install'

"$entry" update >"$test_root/log" 2>&1
[[ $(cat "$DST_ROOT/.build-id") == 12345 ]] || fail 'Build ID'
rg -q '^validate$' "$test_root/update-args" || fail 'First install must validate'
cmp "$MODS_SETUP" "$DST_ROOT/mods/dedicated_server_mods_setup.lua"
"$entry" update >"$test_root/log" 2>&1
if rg -q '^validate$' "$test_root/update-args"; then fail 'Ordinary update unexpectedly validates'; fi
"$entry" update --validate >"$test_root/log" 2>&1
rg -q '^validate$' "$test_root/update-args" || fail 'Explicit repair must validate'
pass 'first install, update, repair and mod setup'

expect_failure env MOCK_STATE=0 "$entry" update
[[ -e $DST_ROOT/.update-incomplete ]] || fail 'Bad manifest must leave incomplete marker'
expect_failure "$entry" run
"$entry" update >"$test_root/log" 2>&1
expect_failure env MOCK_FAIL=1 "$entry" start
[[ -e $DST_ROOT/.update-incomplete ]] || fail 'Failed update must leave marker'
[[ ! -e $test_root/game-ready ]] || fail 'Game started after failed update'
expect_failure "$entry" run
"$entry" update >"$test_root/log" 2>&1
pass 'update failure and invalid manifest cannot start game'

mv "$DATA_ROOT/DoNotStarveTogether/Cluster_1/cluster_token.txt" "$test_root/token"
expect_failure "$entry" start
mv "$test_root/token" "$DATA_ROOT/DoNotStarveTogether/Cluster_1/cluster_token.txt"
pass 'missing token rejected'

"$entry" run >"$test_root/run-log" 2>&1 &
runner=$!
await_file "$test_root/game-ready"
expect_failure "$entry" update
expect_failure "$entry" run
kill -TERM "$runner"
finish_runner 0
[[ -f $test_root/saved && ! -f $test_root/game-signals ]] || fail 'Graceful save did not happen'
rg -q '^Master$' "$test_root/game-args" || fail 'Wrong shard arguments'
pass 'run locks, TERM console shutdown, save and exit code'

rm "$test_root/game-ready" "$test_root/saved"
MOCK_GAME_EXIT=17 "$entry" run >"$test_root/run-log" 2>&1 &
runner=$!
await_file "$test_root/game-ready"
kill -INT "$runner"
# Bash background jobs inherit ignored SIGINT, so use TERM in that case.
# SIGINT from Docker is exercised in the container integration test.
kill -TERM "$runner"
finish_runner 17
pass 'game exit code preserved'

# A different installation must still be prevented from running the same shard.
cp -a "$DST_ROOT" "$test_root/other-game"
rm "$test_root/game-ready"
"$entry" run >"$test_root/run-log" 2>&1 &
runner=$!
await_file "$test_root/game-ready"
expect_failure env DST_ROOT="$test_root/other-game" "$entry" run
kill -TERM "$runner"
finish_runner 0
pass 'shared-data shard lock'

rm "$test_root/update-args" "$test_root/game-ready"
"$entry" start >"$test_root/run-log" 2>&1 &
runner=$!
await_file "$test_root/game-ready"
[[ -f $test_root/update-args ]] || fail 'Start did not update'
kill -TERM "$runner"
finish_runner 0
pass 'start routes through updater'

MOCK_BLOCK=1 "$entry" update >"$test_root/update-log" 2>&1 &
runner=$!
await_file "$test_root/update-ready"
kill -TERM "$runner"
finish_runner 143
[[ -f $test_root/update-stopped && -e $DST_ROOT/.update-incomplete ]] || fail 'Update stop did not preserve incomplete state'
child_pid=$(cat "$test_root/update-child")
if kill -0 "$child_pid" 2>/dev/null; then fail 'Update child leaked'; fi
pass 'update stop terminates process group'

"$entry" update >"$test_root/log" 2>&1
rm "$MODS_SETUP"
"$entry" update >"$test_root/log" 2>&1
if rg -q ServerModSetup "$DST_ROOT/mods/dedicated_server_mods_setup.lua"; then fail 'Missing mod setup kept old list'; fi
pass 'absent mod setup produces empty list'

if [[ $(id -u) != 0 ]]; then
    chmod a-w "$DATA_ROOT/DoNotStarveTogether/Cluster_1/Master"
    expect_failure "$entry" run
    chmod u+w "$DATA_ROOT/DoNotStarveTogether/Cluster_1/Master"
    pass 'unwritable shard rejected'
fi
