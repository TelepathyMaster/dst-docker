#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"
# shellcheck source=scripts/update.sh
source "$SCRIPT_DIR/update.sh"
# shellcheck source=scripts/run.sh
source "$SCRIPT_DIR/run.sh"

command=${1:-start}
shift "$(( $# > 0 ? 1 : 0 ))"
case "$command" in
    start|run) (( $# == 0 )) || die "$command accepts no arguments" ;;
    update) (( $# == 0 )) || [[ $# == 1 && $1 == --validate ]] || die 'Usage: update [--validate]' ;;
    *) die 'Usage: start | run | update [--validate]' ;;
esac
validate_identity
trap stop_child TERM INT
trap cleanup EXIT
lock_install
case "$command" in
    start) validate_config; update_game; run_game ;;
    update) update_game "${1:-}" ;;
    run) validate_config; run_game ;;
esac
