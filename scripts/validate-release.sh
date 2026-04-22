#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

# shellcheck disable=SC1091
. "$SCRIPT_DIR/release-common.sh"

require_command codesign
require_command spctl
require_command xcrun

validated_any=0

if [ -d "$EXPORTED_APP_PATH" ]; then
    validated_any=1
    log "Validating signed app at $EXPORTED_APP_PATH"

    find "$EXPORTED_APP_PATH/Contents" \
        \( -name '*.app' -o -name '*.framework' -o -name '*.xpc' -o -name '*.appex' -o -name '*.systemextension' -o -name '*.dylib' \) \
        | while IFS= read -r nested_path; do
            codesign --verify --strict --verbose=2 "$nested_path"
        done

    codesign --verify --deep --strict --verbose=2 "$EXPORTED_APP_PATH"

    codesign_details=$(codesign -dvvv --entitlements :- "$EXPORTED_APP_PATH" 2>&1)
    printf '%s\n' "$codesign_details" >"$BUILD_DIR/codesign-details.txt"

    printf '%s' "$codesign_details" | grep -q 'Runtime Version' || fail "Hardened runtime is not enabled for $EXPORTED_APP_PATH"
    printf '%s' "$codesign_details" | grep -q '<plist' || fail "Embedded entitlements are missing for $EXPORTED_APP_PATH"

    spctl -a -vv "$EXPORTED_APP_PATH"
fi

if [ -f "$DMG_PATH" ]; then
    validated_any=1
    log "Validating DMG at $DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
    spctl -a -vv -t open "$DMG_PATH"
fi

[ "$validated_any" -eq 1 ] || fail "No release artifact found. Expected app at $EXPORTED_APP_PATH or DMG at $DMG_PATH"
log "Release validation completed"
