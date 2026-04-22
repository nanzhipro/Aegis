#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

# shellcheck disable=SC1091
. "$SCRIPT_DIR/release-common.sh"

require_command codesign
require_command security
prepare_release_directories
prepare_signing_material
require_exported_app

signing_identity=$(resolve_signing_identity)
write_release_env "$signing_identity"

find "$EXPORTED_APP_PATH/Contents" \
    \( -name '*.app' -o -name '*.framework' -o -name '*.xpc' -o -name '*.appex' -o -name '*.systemextension' -o -name '*.dylib' \) \
    | LC_ALL=C sort -r \
    | while IFS= read -r nested_path; do
        codesign_sign_path "$signing_identity" "$nested_path"
    done

codesign_sign_path "$signing_identity" "$EXPORTED_APP_PATH"
codesign --verify --deep --strict --verbose=2 "$EXPORTED_APP_PATH"

log "Signed release app with identity: $signing_identity"
