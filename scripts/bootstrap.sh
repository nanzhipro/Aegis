#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

# shellcheck disable=SC1091
. "$SCRIPT_DIR/release-common.sh"

require_command xcodebuild
require_command codesign
require_command security
require_command xcrun
require_command hdiutil
require_command ruby

require_xcode_version 15.4
require_macos_sdk_version 14.5
prepare_release_directories
prepare_signing_material
prepare_notary_material

signing_identity=""
if signing_identity=$(resolve_signing_identity 2>/dev/null); then
    log "Resolved signing identity: $signing_identity"
else
    warn "No Developer ID Application identity resolved during bootstrap. Signing steps will require one later."
fi

write_release_env "$signing_identity"
log "Bootstrap completed. Release environment metadata written to $RELEASE_ENV_PATH"
