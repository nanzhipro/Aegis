#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

# shellcheck disable=SC1091
. "$SCRIPT_DIR/release-common.sh"

require_command xcrun
prepare_release_directories
prepare_notary_material
require_dmg
notary_keychain_profile=$(resolve_notary_keychain_profile)

if [ -n "$notary_keychain_profile" ]; then
    log "Submitting $DMG_PATH for notarization using keychain profile $notary_keychain_profile"
    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$notary_keychain_profile" \
        --wait \
        --output-format json >"$NOTARY_LOG_PATH"
else
    require_env APPLE_NOTARY_KEY_ID
    require_env APPLE_NOTARY_ISSUER_ID
    require_env APPLE_TEAM_ID
    [ -f "$NOTARY_KEY_PATH" ] || fail "App Store Connect API key not found at $NOTARY_KEY_PATH"

    log "Submitting $DMG_PATH for notarization using App Store Connect API key at $NOTARY_KEY_PATH"
    xcrun notarytool submit "$DMG_PATH" \
        --key "$NOTARY_KEY_PATH" \
        --key-id "$APPLE_NOTARY_KEY_ID" \
        --issuer "$APPLE_NOTARY_ISSUER_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --wait \
        --output-format json >"$NOTARY_LOG_PATH"
fi

xcrun stapler staple "$DMG_PATH"

log "Notarized and stapled $DMG_PATH"
log "Notary submission log saved to $NOTARY_LOG_PATH"
