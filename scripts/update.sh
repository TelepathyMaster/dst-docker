#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
# Sourced by the supervisor so signals and lifecycle locks have one owner.
update_game() {
    local repair=${1:-} status=0
    local -a update_args=(+app_update 343050)
    (( stop_requested == 0 )) || exit 143
    mkdir -p "$DST_ROOT/.home/.steam" "$DST_ROOT/.steamcmd"
    # SteamCMD self-updates in this writable shared directory.
    if [[ ! -x $DST_ROOT/.steamcmd/steamcmd.sh ]]; then
        cp -a "$STEAMCMD_BOOTSTRAP/." "$DST_ROOT/.steamcmd/"
    fi
    [[ -x $GAME && -s $MANIFEST && ! -e $DST_ROOT/.update-incomplete && $repair != --validate ]] || update_args+=(validate)
    rm -f "$DST_ROOT/.mods-ready"
    touch "$DST_ROOT/.update-incomplete"
    phase=update
    log 'Installing/updating Steam App 343050'
    setsid "$DST_ROOT/.steamcmd/steamcmd.sh" +force_install_dir "$DST_ROOT" +login anonymous "${update_args[@]}" +quit &
    active_child=$!
    (( stop_requested == 0 )) || stop_child
    wait_child || status=$?
    (( stop_requested == 0 )) || exit 143
    (( status == 0 )) || die "SteamCMD failed (exit $status); installation marked incomplete"
    # Validate before removing the incomplete marker.
    [[ -x $GAME && -s $MANIFEST ]] || die 'SteamCMD returned without a usable installation'
    validate_install updating
    build_id >"$DST_ROOT/.build-id"
    ln -sfn "$DST_ROOT/.steamcmd/linux32" "$DST_ROOT/.home/.steam/sdk32"
    ln -sfn "$DST_ROOT/.steamcmd/linux64" "$DST_ROOT/.home/.steam/sdk64"
    sync_mods
    rm -f "$DST_ROOT/.update-incomplete"
    log "Installed Steam Build ID $(build_id)"
    phase=idle
}

update_mods() {
    local status=0 signature
    signature=$(mods_signature)
    touch "$DST_ROOT/.mods-incomplete"
    phase=mods
    cd "$DST_ROOT/bin64" || die 'Cannot enter game bin64 directory'
    log 'Downloading/updating shared Workshop mods'
    setsid "$GAME" -only_update_server_mods -ugc_directory "$DST_ROOT/ugc_mods" \
        -persistent_storage_root "$DATA_ROOT" -conf_dir DoNotStarveTogether \
        -cluster "$CLUSTER_NAME" -shard "$SHARD" >"$DST_ROOT/.mods-update.log" 2>&1 &
    active_child=$!
    (( stop_requested == 0 )) || stop_child
    wait_child || status=$?
    (( stop_requested == 0 )) || exit 143
    cat "$DST_ROOT/.mods-update.log"
    if grep -Eq 'ODPF failed entirely|OnDownloadPublishedFile \[([02-9]|[0-9]{2,})\]|LUA ERROR' "$DST_ROOT/.mods-update.log"; then
        die 'Workshop download failed; mods marked incomplete (see .mods-update.log)'
    fi
    (( status == 0 )) || die "Mod updater failed (exit $status); mods marked incomplete"
    [[ $signature == "$(mods_signature)" ]] || die 'Mod download list changed during update; retry update'
    printf '%s\n' "$signature" >"$DST_ROOT/.mods-ready"
    rm -f "$DST_ROOT/.mods-incomplete"
    phase=idle
    log 'Shared game and mods are ready'
}
