#!/usr/bin/env bash
# shellcheck disable=SC2034
# Path overrides are internal test hooks; the container uses the defaults.
DST_ROOT=${DST_ROOT:-/opt/dst}
DATA_ROOT=${DATA_ROOT:-/data}
MODS_SETUP=${MODS_SETUP:-/config/dedicated_server_mods_setup.lua}
STEAMCMD_BOOTSTRAP=${STEAMCMD_BOOTSTRAP:-/usr/local/share/steamcmd}
CLUSTER_NAME=${CLUSTER_NAME:-Cluster_1}
SHARD=${SHARD:-Master}
GAME="$DST_ROOT/bin64/dontstarve_dedicated_server_nullrenderer_x64"
MANIFEST="$DST_ROOT/steamapps/appmanifest_343050.acf"
CLUSTER_DIR="$DATA_ROOT/DoNotStarveTogether/$CLUSTER_NAME"
active_child=
phase=idle
stop_requested=0
console_dir=
shutdown_timer=
shutdown_sent=0

log() { printf '[dst] %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

validate_identity() {
    [[ $CLUSTER_NAME =~ ^[A-Za-z0-9_-]+$ ]] || die 'CLUSTER_NAME must contain only letters, numbers, _ or -'
    [[ $SHARD == Master || $SHARD == Caves ]] || die 'SHARD must be Master or Caves'
}

lock_install() {
    mkdir -p "$DST_ROOT" || die 'Cannot create /opt/dst; check Volume ownership'
    [[ -w $DST_ROOT ]] || die 'Game Volume is not writable; prepare ownership for the container UID/GID'
    exec {install_lock}>"$DST_ROOT/.lifecycle.lock"
    flock -n "$install_lock" || die 'Game Volume is busy: stop the container before updating'
}

validate_config() {
    local file
    for file in cluster.ini cluster_token.txt "$SHARD/server.ini"; do
        [[ -s "$CLUSTER_DIR/$file" && -r "$CLUSTER_DIR/$file" ]] || die "Missing or unreadable cluster file: $file"
    done
    [[ -w $CLUSTER_DIR && -w $CLUSTER_DIR/$SHARD ]] || die 'Cluster and shard directories must be writable'
    mkdir -p "$DATA_ROOT/.locks"
    exec {shard_lock}>"$DATA_ROOT/.locks/${CLUSTER_NAME}_${SHARD}.lock"
    flock -n "$shard_lock" || die "Shard $CLUSTER_NAME/$SHARD is already running"
}

build_id() {
    [[ -s $MANIFEST ]] || return 1
    awk -F '"' '$2 == "buildid" && $4 ~ /^[0-9]+$/ { print $4; found=1; exit } END { if (!found) exit 1 }' "$MANIFEST"
}

validate_install() {
    [[ ${1:-} == updating || ! -e $DST_ROOT/.update-incomplete ]] || die 'Previous update was interrupted or failed; run update again'
    [[ -x $GAME ]] || die 'Game executable is missing; run update first'
    [[ -s $MANIFEST ]] || die 'Steam installation manifest is missing; run update first'
    awk -F '"' '$2 == "appid" && $4 == "343050" { app=1 } $2 == "StateFlags" && $4 == "4" { ready=1 } END { exit !(app && ready) }' "$MANIFEST" \
        || die 'Steam installation manifest is incomplete; run update again'
    build_id >/dev/null || die 'Steam Build ID is missing'
}

sync_mods() {
    mkdir -p "$DST_ROOT/mods"
    if [[ -e $MODS_SETUP ]]; then
        [[ -f $MODS_SETUP && -r $MODS_SETUP ]] || die 'Mod setup must be a readable Lua file'
        cp "$MODS_SETUP" "$DST_ROOT/mods/dedicated_server_mods_setup.lua"
    else
        printf '%s\n' '-- No Workshop mods configured.' >"$DST_ROOT/mods/dedicated_server_mods_setup.lua"
    fi
}

arm_kill_timer() {
    [[ -z $shutdown_timer ]] || return 0
    # shellcheck disable=SC2016
    setsid bash -c 'sleep "$2"; printf "[dst] Stop timed out; terminating child\n" >&2; kill -TERM -- "-$1" 2>/dev/null || true; sleep 5; kill -KILL -- "-$1" 2>/dev/null || true' _ "$active_child" "$1" &
    shutdown_timer=$!
}

stop_child() {
    stop_requested=1
    [[ -n $active_child ]] || return 0
    if [[ $phase == game ]]; then
        (( shutdown_sent == 0 )) || return 0
        # Send the shutdown command before ending console input.
        if printf 'c_shutdown()\n' >&3; then
            shutdown_sent=1
            # Release stdin after the command. DST joins its console reader on
            # shutdown; an open FIFO writer can leave that thread blocked.
            # Close before spawning the timer so it cannot inherit the writer.
            exec 3>&-
            log 'Shutdown requested; waiting for world save'
            # Docker allows 120s; leave 10s for process cleanup.
            arm_kill_timer 110
        else
            log 'Console shutdown failed; terminating game'
            kill -TERM -- "-$active_child" 2>/dev/null || true
            arm_kill_timer 5
        fi
    else
        log 'Stopping installation/update'
        kill -TERM -- "-$active_child" 2>/dev/null || true
        arm_kill_timer 5
    fi
}

wait_child() {
    local status=0 final_status=0
    # A trapped signal interrupts Bash wait; wait again until the child really exits.
    while true; do
        wait "$active_child" && status=0 || status=$?
        if ! kill -0 "$active_child" 2>/dev/null; then break; fi
    done
    # If the child exited while the trap ran, the interrupted wait reported the
    # signal rather than the child's status. Bash retains the status for re-wait.
    wait "$active_child" && final_status=0 || final_status=$?
    if (( final_status != 127 )); then status=$final_status; fi
    active_child=
    return "$status"
}

cleanup() {
    local status=$?
    trap - EXIT TERM INT
    if [[ -n $active_child ]]; then
        kill -TERM -- "-$active_child" 2>/dev/null || true
        sleep 1
        kill -KILL -- "-$active_child" 2>/dev/null || true
        wait "$active_child" 2>/dev/null || true
    fi
    if [[ -n $shutdown_timer ]]; then
        # Timer is launched in a separate session; kill its sleep children as well.
        # It may not have called setsid yet when a fast game exits.
        kill -TERM "$shutdown_timer" 2>/dev/null || true
        kill -TERM -- "-$shutdown_timer" 2>/dev/null || true
        wait "$shutdown_timer" 2>/dev/null || true
    fi
    [[ -z $console_dir ]] || rm -rf "$console_dir"
    exit "$status"
}
