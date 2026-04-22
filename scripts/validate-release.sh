#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

# shellcheck disable=SC1091
. "$SCRIPT_DIR/release-common.sh"

require_command codesign
require_command spctl
require_command xcrun
require_command ditto
prepare_release_directories
require_exported_app
require_packaged_zip

agent_app_path="$EXPORTED_APP_PATH/Contents/Library/LoginItems/AegisAgent.app"
extension_path="$EXPORTED_APP_PATH/Contents/Library/SystemExtensions/AegisExtension.systemextension"

[ -d "$agent_app_path" ] || fail "Embedded agent app not found at $agent_app_path"
[ -d "$extension_path" ] || fail "Embedded system extension not found at $extension_path"

log "Validating signed app at $EXPORTED_APP_PATH"

find "$EXPORTED_APP_PATH/Contents" \
    \( -name '*.app' -o -name '*.framework' -o -name '*.xpc' -o -name '*.appex' -o -name '*.systemextension' -o -name '*.dylib' \) \
    | while IFS= read -r nested_path; do
        codesign --verify --strict --verbose=2 "$nested_path"
    done

codesign --verify --deep --strict --verbose=3 "$EXPORTED_APP_PATH"

codesign_details=$(codesign -dvvv --entitlements :- "$EXPORTED_APP_PATH" 2>&1)
printf '%s\n' "$codesign_details" >"$BUILD_DIR/codesign-details-app.txt"
printf '%s' "$codesign_details" | grep -q 'Runtime Version' || fail "Hardened runtime is not enabled for $EXPORTED_APP_PATH"
printf '%s' "$codesign_details" | grep -q '<plist' || fail "Embedded entitlements are missing for $EXPORTED_APP_PATH"

codesign -dvvv --entitlements :- "$agent_app_path" >"$BUILD_DIR/codesign-details-agent.txt" 2>&1
codesign -dvvv --entitlements :- "$extension_path" >"$BUILD_DIR/codesign-details-extension.txt" 2>&1

grep -q '<plist' "$BUILD_DIR/codesign-details-agent.txt" || fail "Embedded entitlements are missing for $agent_app_path"
grep -q '<plist' "$BUILD_DIR/codesign-details-extension.txt" || fail "Embedded entitlements are missing for $extension_path"

spctl --assess --type execute -vv "$EXPORTED_APP_PATH"
xcrun stapler validate "$EXPORTED_APP_PATH"

zip_validation_root=$(mktemp -d "$BUILD_DIR/zip-validate.XXXXXX")
trap 'rm -rf "$zip_validation_root"' EXIT INT TERM HUP
ditto -x -k "$ZIP_PATH" "$zip_validation_root"

extracted_app_path="$zip_validation_root/$(basename -- "$EXPORTED_APP_PATH")"
[ -d "$extracted_app_path" ] || fail "ZIP did not contain $(basename -- "$EXPORTED_APP_PATH")"
xcrun stapler validate "$extracted_app_path"

log "Release validation completed"
