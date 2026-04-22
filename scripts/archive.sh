#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

# shellcheck disable=SC1091
. "$SCRIPT_DIR/release-common.sh"

require_command xcodebuild
prepare_release_directories

rm -rf "$ARCHIVE_PATH" "$EXPORTED_APP_PATH"

xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$APP_SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE_PATH" \
    archive \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY=""

archived_app_path="$ARCHIVE_PATH/Products/Applications/AegisApp.app"
[ -d "$archived_app_path" ] || fail "Archive did not produce $archived_app_path"

ditto "$archived_app_path" "$EXPORTED_APP_PATH"
log "Archive created at $ARCHIVE_PATH"
log "Exported app staged at $EXPORTED_APP_PATH"
