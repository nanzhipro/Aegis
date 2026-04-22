#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

# shellcheck disable=SC1091
. "$SCRIPT_DIR/release-common.sh"

require_command hdiutil
prepare_release_directories
require_exported_app

staging_dir="$BUILD_DIR/dmg-root"
rm -rf "$staging_dir" "$DMG_PATH"
mkdir -p "$staging_dir"

ditto "$EXPORTED_APP_PATH" "$staging_dir/$(basename -- "$EXPORTED_APP_PATH")"
ln -s /Applications "$staging_dir/Applications"

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$staging_dir" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

log "Packaged DMG at $DMG_PATH"
