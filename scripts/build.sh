#!/usr/bin/env bash
# Build Bluke Free on Linux or macOS.
#
#   ./scripts/build.sh                          debug APK
#   ./scripts/build.sh --release --keystore ~/keys/my-upload-key.jks
#   ./scripts/build.sh --install                debug APK, installed over USB
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE=0
INSTALL=0
DEVICE=""
KEYSTORE=""
STORE_PASSWORD=""
KEY_ALIAS="k0"
KEY_PASSWORD=""

while [ $# -gt 0 ]; do
    case "$1" in
        --release) RELEASE=1; shift ;;
        --install) INSTALL=1; shift ;;
        --device) DEVICE="$2"; shift 2 ;;
        --keystore) KEYSTORE="$2"; shift 2 ;;
        --store-password) STORE_PASSWORD="$2"; shift 2 ;;
        --key-alias) KEY_ALIAS="$2"; shift 2 ;;
        --key-password) KEY_PASSWORD="$2"; shift 2 ;;
        -h|--help) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

if [ ! -f "$ROOT/local.properties" ] && [ -z "${ANDROID_HOME:-}" ] && [ -z "${ANDROID_SDK_ROOT:-}" ]; then
    echo "Android SDK not configured. Run ./scripts/setup.sh once (or set ANDROID_HOME)." >&2
    exit 1
fi

if [ -n "$KEYSTORE" ]; then
    [ -f "$KEYSTORE" ] || { echo "keystore not found: $KEYSTORE" >&2; exit 1; }
    export KEYSTORE_PATH="$KEYSTORE"
    export KEY_ALIAS
    if [ -z "$STORE_PASSWORD" ]; then
        read -rsp "Keystore password: " STORE_PASSWORD; echo
    fi
    export STORE_PASSWORD
    export KEY_PASSWORD="${KEY_PASSWORD:-$STORE_PASSWORD}"
    RELEASE=1
fi

if [ "$INSTALL" -eq 1 ]; then
    TASK=installDebug
elif [ "$RELEASE" -eq 1 ]; then
    TASK=assembleRelease
else
    TASK=assembleDebug
fi

cd "$ROOT"
echo "==> ./gradlew $TASK --console=plain"
if [ -n "$DEVICE" ]; then
    ./gradlew "$TASK" --console=plain "-Pandroid.injected.device.serial=$DEVICE"
else
    ./gradlew "$TASK" --console=plain
fi

VARIANT=debug
[ "$RELEASE" -eq 1 ] && VARIANT=release
APK="$(find "$ROOT/app/build/outputs/apk/$VARIANT" -name '*.apk' -print 2>/dev/null | head -1)"
if [ -n "$APK" ]; then
    echo
    echo "APK: $APK"
    echo "     $(du -h "$APK" | cut -f1)"
else
    echo "warning: build finished but no APK found under app/build/outputs/apk/$VARIANT" >&2
fi
