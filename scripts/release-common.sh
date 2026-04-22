#!/bin/sh

ROOT_DIR=${ROOT_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
BUILD_DIR=${AEGIS_BUILD_DIR:-"$ROOT_DIR/build/release"}
DERIVED_DATA_DIR=${AEGIS_DERIVED_DATA_DIR:-"$ROOT_DIR/DerivedData/Release"}
PROJECT_PATH=${AEGIS_PROJECT_PATH:-"$ROOT_DIR/Aegis.xcodeproj"}
APP_SCHEME=${AEGIS_APP_SCHEME:-AegisApp}
CONFIGURATION=${AEGIS_CONFIGURATION:-Release}
ARCHIVE_PATH=${AEGIS_ARCHIVE_PATH:-"$BUILD_DIR/Aegis.xcarchive"}
EXPORTED_APP_PATH=${AEGIS_EXPORTED_APP_PATH:-"$BUILD_DIR/AegisApp.app"}
DMG_PATH=${AEGIS_DMG_PATH:-"$BUILD_DIR/AegisApp.dmg"}
VOLUME_NAME=${AEGIS_VOLUME_NAME:-Aegis}
RELEASE_ENV_PATH=${AEGIS_RELEASE_ENV_PATH:-"$BUILD_DIR/release.env"}
KEYCHAIN_PATH=${AEGIS_KEYCHAIN_PATH:-"$BUILD_DIR/aegis-signing.keychain-db"}
CERTIFICATE_PATH=${AEGIS_CERTIFICATE_PATH:-"$BUILD_DIR/developer-id.p12"}
NOTARY_KEY_PATH=${AEGIS_NOTARY_KEY_PATH:-"$BUILD_DIR/notary-api-key.p8"}
NOTARY_LOG_PATH=${AEGIS_NOTARY_LOG_PATH:-"$BUILD_DIR/notary-submit.json"}

if [ -f "$RELEASE_ENV_PATH" ]; then
    # shellcheck disable=SC1090
    . "$RELEASE_ENV_PATH"
fi

log() {
    printf '%s\n' "[aegis-release] $*"
}

warn() {
    printf '%s\n' "[aegis-release] warning: $*" >&2
}

fail() {
    printf '%s\n' "[aegis-release] error: $*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

require_env() {
    eval "value=\${$1:-}"
    [ -n "$value" ] || fail "Missing required environment variable: $1"
}

resolve_notary_keychain_profile() {
    if [ -n "${AEGIS_NOTARY_KEYCHAIN_PROFILE:-}" ]; then
        printf '%s' "$AEGIS_NOTARY_KEYCHAIN_PROFILE"
        return
    fi

    if [ -n "${APPLE_NOTARY_KEYCHAIN_PROFILE:-}" ]; then
        printf '%s' "$APPLE_NOTARY_KEYCHAIN_PROFILE"
    fi
}

prepare_release_directories() {
    mkdir -p "$BUILD_DIR" "$DERIVED_DATA_DIR"
}

version_gte() {
    awk -v left="$1" -v right="$2" '
        BEGIN {
            split(left, lhs, ".")
            split(right, rhs, ".")
            max = length(lhs) > length(rhs) ? length(lhs) : length(rhs)
            for (i = 1; i <= max; i++) {
                l = (i in lhs) ? lhs[i] + 0 : 0
                r = (i in rhs) ? rhs[i] + 0 : 0
                if (l > r) {
                    exit 0
                }
                if (l < r) {
                    exit 1
                }
            }
            exit 0
        }
    '
}

require_xcode_version() {
    minimum_version="$1"
    current_version=$(xcodebuild -version | awk 'NR == 1 { print $2 }')
    version_gte "$current_version" "$minimum_version" || fail "Xcode $minimum_version or newer is required. Found $current_version."
}

require_macos_sdk_version() {
    minimum_version="$1"
    current_version=$(xcrun --sdk macosx --show-sdk-version)
    version_gte "$current_version" "$minimum_version" || fail "macOS SDK $minimum_version or newer is required. Found $current_version."
}

decode_base64_to_file() {
    input="$1"
    output_path="$2"

    if printf '%s' "$input" | base64 -D >"$output_path" 2>/dev/null; then
        return
    fi

    if printf '%s' "$input" | base64 --decode >"$output_path" 2>/dev/null; then
        return
    fi

    fail "Unable to decode base64 content for $output_path"
}

prepare_signing_material() {
    if [ -z "${DEVELOPER_ID_P12_BASE64:-}" ]; then
        return
    fi

    require_command security
    require_env DEVELOPER_ID_P12_PASSWORD
    require_env KEYCHAIN_PASSWORD
    prepare_release_directories

    rm -f "$CERTIFICATE_PATH"
    decode_base64_to_file "$DEVELOPER_ID_P12_BASE64" "$CERTIFICATE_PATH"

    security delete-keychain "$KEYCHAIN_PATH" >/dev/null 2>&1 || true
    security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null
    security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH" >/dev/null
    security import "$CERTIFICATE_PATH" \
        -k "$KEYCHAIN_PATH" \
        -P "$DEVELOPER_ID_P12_PASSWORD" \
        -T /usr/bin/codesign \
        -T /usr/bin/security >/dev/null
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null

    log "Prepared temporary signing keychain at $KEYCHAIN_PATH"
}

prepare_notary_material() {
    if [ -n "$(resolve_notary_keychain_profile)" ]; then
        return
    fi

    if [ -z "${APPLE_NOTARY_PRIVATE_KEY:-}" ]; then
        return
    fi

    require_env APPLE_NOTARY_KEY_ID
    require_env APPLE_NOTARY_ISSUER_ID
    require_env APPLE_TEAM_ID
    prepare_release_directories

    rm -f "$NOTARY_KEY_PATH"

    case "$APPLE_NOTARY_PRIVATE_KEY" in
        *"BEGIN PRIVATE KEY"*)
            printf '%s\n' "$APPLE_NOTARY_PRIVATE_KEY" >"$NOTARY_KEY_PATH"
            ;;
        *)
            decode_base64_to_file "$APPLE_NOTARY_PRIVATE_KEY" "$NOTARY_KEY_PATH"
            ;;
    esac

    chmod 600 "$NOTARY_KEY_PATH"
    log "Prepared App Store Connect API key at $NOTARY_KEY_PATH"
}

resolve_signing_identity() {
    if [ -n "${AEGIS_SIGNING_IDENTITY:-}" ]; then
        printf '%s' "$AEGIS_SIGNING_IDENTITY"
        return
    fi

    if [ -n "${DEVELOPER_ID_APPLICATION:-}" ]; then
        printf '%s' "$DEVELOPER_ID_APPLICATION"
        return
    fi

    if [ -f "$KEYCHAIN_PATH" ]; then
        identity=$(security find-identity -v -p codesigning "$KEYCHAIN_PATH" 2>/dev/null | awk -F '"' '/Developer ID Application/ { print $2; exit }')
    else
        identity=$(security find-identity -v -p codesigning 2>/dev/null | awk -F '"' '/Developer ID Application/ { print $2; exit }')
    fi

    [ -n "$identity" ] || fail "Unable to locate a Developer ID Application signing identity."
    printf '%s' "$identity"
}

quote_for_shell() {
    if [ -z "$1" ]; then
        printf "''"
        return
    fi

    printf '%s' "$1" | sed "s/'/'\\''/g; 1s/^/'/; \$s/\$/'/"
}

write_release_env() {
    signing_identity="${1:-}"
    notary_keychain_profile=$(resolve_notary_keychain_profile)
    prepare_release_directories

    {
        printf 'export AEGIS_BUILD_DIR=%s\n' "$(quote_for_shell "$BUILD_DIR")"
        printf 'export AEGIS_DERIVED_DATA_DIR=%s\n' "$(quote_for_shell "$DERIVED_DATA_DIR")"
        printf 'export AEGIS_PROJECT_PATH=%s\n' "$(quote_for_shell "$PROJECT_PATH")"
        printf 'export AEGIS_APP_SCHEME=%s\n' "$(quote_for_shell "$APP_SCHEME")"
        printf 'export AEGIS_CONFIGURATION=%s\n' "$(quote_for_shell "$CONFIGURATION")"
        printf 'export AEGIS_ARCHIVE_PATH=%s\n' "$(quote_for_shell "$ARCHIVE_PATH")"
        printf 'export AEGIS_EXPORTED_APP_PATH=%s\n' "$(quote_for_shell "$EXPORTED_APP_PATH")"
        printf 'export AEGIS_DMG_PATH=%s\n' "$(quote_for_shell "$DMG_PATH")"
        printf 'export AEGIS_VOLUME_NAME=%s\n' "$(quote_for_shell "$VOLUME_NAME")"
        printf 'export AEGIS_KEYCHAIN_PATH=%s\n' "$(quote_for_shell "$KEYCHAIN_PATH")"
        printf 'export AEGIS_CERTIFICATE_PATH=%s\n' "$(quote_for_shell "$CERTIFICATE_PATH")"
        printf 'export AEGIS_NOTARY_KEY_PATH=%s\n' "$(quote_for_shell "$NOTARY_KEY_PATH")"
        printf 'export AEGIS_NOTARY_LOG_PATH=%s\n' "$(quote_for_shell "$NOTARY_LOG_PATH")"

        if [ -n "$notary_keychain_profile" ]; then
            printf 'export AEGIS_NOTARY_KEYCHAIN_PROFILE=%s\n' "$(quote_for_shell "$notary_keychain_profile")"
        fi

        if [ -n "$signing_identity" ]; then
            printf 'export AEGIS_SIGNING_IDENTITY=%s\n' "$(quote_for_shell "$signing_identity")"
        fi
    } >"$RELEASE_ENV_PATH"
}

codesign_sign_path() {
    signing_identity="$1"
    target_path="$2"
    entitlements_path=""

    case "$(basename -- "$target_path")" in
        AegisApp.app)
            entitlements_path="$ROOT_DIR/AegisApp/AegisApp.entitlements"
            ;;
        AegisAgent.app)
            entitlements_path="$ROOT_DIR/AegisAgent/AegisAgent.entitlements"
            ;;
        AegisExtension.systemextension)
            entitlements_path="$ROOT_DIR/AegisExtension/AegisExtension.entitlements"
            ;;
    esac

    if [ -f "$KEYCHAIN_PATH" ]; then
        if [ -n "$entitlements_path" ] && [ -f "$entitlements_path" ]; then
            codesign --force --sign "$signing_identity" --keychain "$KEYCHAIN_PATH" --options runtime --timestamp --preserve-metadata=identifier --entitlements "$entitlements_path" "$target_path"
            return
        fi

        codesign --force --sign "$signing_identity" --keychain "$KEYCHAIN_PATH" --options runtime --timestamp --preserve-metadata=identifier "$target_path"
        return
    fi

    if [ -n "$entitlements_path" ] && [ -f "$entitlements_path" ]; then
        codesign --force --sign "$signing_identity" --options runtime --timestamp --preserve-metadata=identifier --entitlements "$entitlements_path" "$target_path"
        return
    fi

    codesign --force --sign "$signing_identity" --options runtime --timestamp --preserve-metadata=identifier "$target_path"
}

require_exported_app() {
    [ -d "$EXPORTED_APP_PATH" ] || fail "Exported app not found at $EXPORTED_APP_PATH"
}

require_dmg() {
    [ -f "$DMG_PATH" ] || fail "DMG not found at $DMG_PATH"
}
