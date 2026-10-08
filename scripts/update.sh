#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
# Sourced by the supervisor so signals and lifecycle locks have one owner.
update_game() {
    local repair=${1:-} status=0
    local -a update_args=(+app_update 343050)
    (( stop_requested == 0 )) || exit 143
    mkdir -p "$DST_ROOT/.home/.steam" "$DST_ROOT/.steamcmd"
    # SteamCMD self-updates in this writable per-shard directory.
    if [[ ! -x $DST_ROOT/.steamcmd/steamcmd.sh ]]; then
        cp -a "$STEAMCMD_BOOTSTRAP/." "$DST_ROOT/.steamcmd/"
    fi
    [[ -x $GAME && -s $MANIFEST && ! -e $DST_ROOT/.update-incomplete && $repair != --validate ]] || update_args+=(validate)
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
