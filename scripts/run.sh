#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
run_game() {
    local status=0
    validate_install
    validate_mods
    prepare_runtime_home
    (( stop_requested == 0 )) || exit 143
    console_dir=$(mktemp -d)
    mkfifo "$console_dir/console"
    exec 3<>"$console_dir/console"
    phase=game
    cd "$DST_ROOT/bin64" || die 'Cannot enter game bin64 directory'
    log "Starting $CLUSTER_NAME/$SHARD (Steam Build ID $(build_id))"
    setsid "$GAME" -console -skip_update_server_mods -ugc_directory "$DST_ROOT/ugc_mods" -persistent_storage_root "$DATA_ROOT" \
        -conf_dir DoNotStarveTogether -cluster "$CLUSTER_NAME" -shard "$SHARD" \
        <"$console_dir/console" 3>&- &
    active_child=$!
    (( stop_requested == 0 )) || stop_child
    wait_child || status=$?
    exec 3>&-
    return "$status"
}
