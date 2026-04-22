#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

# shellcheck disable=SC1091
. "$SCRIPT_DIR/release-common.sh"

require_command ditto
prepare_release_directories
require_exported_app

rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$EXPORTED_APP_PATH" "$ZIP_PATH"

log "Packaged release ZIP at $ZIP_PATH"