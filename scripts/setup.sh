#!/usr/bin/env bash
# One-shot setup for building Bluke Free on Linux or macOS.
#
#   ./scripts/setup.sh                 # install JDK 17 + Android SDK, then build
#   ./scripts/setup.sh --no-build      # set up only
#   ./scripts/setup.sh --sdk-root ~/Android/Sdk
#
# Termux/Android: this script refuses to install a local SDK (too heavy for a
# phone). Use GitHub Actions instead — see docs/PC-SETUP.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Android/Sdk}}"
SKIP_JDK=0
SKIP_SDK=0
DO_BUILD=1

while [ $# -gt 0 ]; do
    case "$1" in
        --sdk-root) SDK_ROOT="$2"; shift 2 ;;
        --skip-jdk) SKIP_JDK=1; shift ;;
        --skip-sdk) SKIP_SDK=1; shift ;;
        --no-build) DO_BUILD=0; shift ;;
        -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

step() { printf '\n\033[36m==> %s\033[0m\n' "$1"; }
info() { printf '    %s\n' "$1"; }
warn() { printf '    !  %s\n' "$1"; }
die()  { printf '    x  %s\n' "$1" >&2; exit 1; }

if [ -n "${TERMUX_VERSION:-}" ] || [ "${PREFIX:-}" = "/data/data/com.termux/files/usr" ]; then
    cat <<'EOF'
This looks like Termux on Android.

A local Android SDK needs ~2-3 GB and a full JDK toolchain; it is not a good
fit for a phone. Builds for this project run on GitHub Actions instead:

    gh workflow run build.yml -R alif-primary/Bluke
    gh run watch -R alif-primary/Bluke
    gh release download -R alif-primary/Bluke --dir ~/apk-archive

Grab the APK from https://github.com/alif-primary/Bluke/releases
EOF
    exit 0
fi

java_major() {
    command -v java >/dev/null 2>&1 || { echo 0; return; }
    local v
    v="$(java -version 2>&1 | head -1 | sed -E 's/.*"([0-9]+).*/\1/')"
    echo "${v:-0}"
}

install_jdk() {
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update -qq && sudo apt-get install -y openjdk-17-jdk
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y java-17-openjdk-devel
    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -Sy --noconfirm jdk17-openjdk
    elif command -v zypper >/dev/null 2>&1; then
        sudo zypper install -y java-17-openjdk-devel
    elif command -v brew >/dev/null 2>&1; then
        brew install --quiet openjdk@17
    else
        die "no supported package manager found; install a JDK 17 manually and re-run with --skip-jdk"
    fi
}

cldtools_url() {
    local os="$1" arch="$2" pinned
    case "$os" in
        linux) pinned='commandlinetools-linux-16111833_latest.zip' ;;
        darwin)
            if [ "$arch" = "arm64" ]; then pinned='commandlinetools-mac_arm64-16111833_latest.zip'
            else pinned='commandlinetools-mac_x86_64-16111833_latest.zip'; fi ;;
        *) die "unsupported OS: $os" ;;
    esac

    local xml name
    if command -v curl >/dev/null 2>&1; then
        xml="$(curl -fsSL --max-time 60 https://dl.google.com/android/repository/repository2-3.xml 2>/dev/null || true)"
        if [ -n "$xml" ]; then
            case "$os" in
                linux) name="$(printf '%s' "$xml" | grep -oE 'commandlinetools-linux-[0-9]+_latest\.zip' | head -1)" ;;
                darwin)
                    if [ "$arch" = "arm64" ]; then
                        name="$(printf '%s' "$xml" | grep -oE 'commandlinetools-mac_arm64-[0-9]+_latest\.zip' | head -1)"
                    else
                        name="$(printf '%s' "$xml" | grep -oE 'commandlinetools-mac_x86_64-[0-9]+_latest\.zip' | head -1)"
                    fi ;;
            esac
            [ -n "$name" ] && { echo "https://dl.google.com/android/repository/$name"; return; }
        fi
    fi
    echo "https://dl.google.com/android/repository/$pinned"
}

# ------------------------------------------------------------------ JDK ----
step "Java 17"
if [ "$SKIP_JDK" -eq 1 ]; then
    info "skipped"
else
    major="$(java_major)"
    if [ "$major" -ge 17 ] 2>/dev/null; then
        info "found $(command -v java) (major $major)"
    else
        info "installing a JDK 17"
        install_jdk
        major="$(java_major)"
        [ "$major" -ge 17 ] 2>/dev/null || die "JDK 17 install did not take effect; open a new shell and re-run"
        info "java major $major"
    fi
fi

# ------------------------------------------------------------ Android SDK --
if [ "$SKIP_SDK" -eq 1 ]; then
    step "Android SDK"
    info "skipped"
else
    step "Android SDK ($SDK_ROOT)"
    SDKMANAGER="$SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"

    if [ ! -x "$SDKMANAGER" ]; then
        mkdir -p "$SDK_ROOT/cmdline-tools"
        url="$(cldtools_url "$(uname -s | tr '[:upper:]' '[:lower:]')" "$(uname -m)")"
        info "downloading $url"
        tmp="$(mktemp -d)"
        trap 'rm -rf "$tmp"' EXIT
        if command -v curl >/dev/null 2>&1; then
            curl -fL --progress-bar "$url" -o "$tmp/cmdline-tools.zip"
        else
            wget -q --show-progress "$url" -O "$tmp/cmdline-tools.zip"
        fi
        unzip -q "$tmp/cmdline-tools.zip" -d "$tmp"
        rm -rf "$SDK_ROOT/cmdline-tools/latest"
        mv "$tmp/cmdline-tools" "$SDK_ROOT/cmdline-tools/latest"
        SDKMANAGER="$SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"
        info "installed $SDKMANAGER"
    else
        info "command-line tools already present"
    fi

    export ANDROID_HOME="$SDK_ROOT"
    export ANDROID_SDK_ROOT="$SDK_ROOT"

    step "Accepting SDK licences"
    { yes 2>/dev/null || true; } | "$SDKMANAGER" --sdk_root="$SDK_ROOT" --licenses >/dev/null 2>&1 || true
    info "licences accepted"

    step "Installing SDK packages"
    for pkg in platform-tools platforms\;android-36.1 build-tools\;36.1.0; do
        if "$SDKMANAGER" --sdk_root="$SDK_ROOT" "$pkg" >/dev/null 2>&1; then
            info "installed $pkg"
        else
            warn "$pkg not installed (Gradle can fetch it on first build)"
        fi
    done

    printf 'sdk.dir=%s\n' "$SDK_ROOT" > "$ROOT/local.properties"
    info "wrote $ROOT/local.properties"

    shell_rc="$HOME/.bashrc"
    [ -n "${ZSH_VERSION:-}" ] && shell_rc="$HOME/.zshrc"
    if ! grep -qs 'ANDROID_HOME' "$shell_rc" 2>/dev/null; then
        printf '\nexport ANDROID_HOME="%s"\nexport PATH="$ANDROID_HOME/platform-tools:$PATH"\n' "$SDK_ROOT" >> "$shell_rc"
        info "added ANDROID_HOME to $shell_rc (new shells only)"
    fi
fi

# ---------------------------------------------------------------- build ----
if [ "$DO_BUILD" -eq 1 ]; then
    step "Building debug APK"
    "$ROOT/scripts/build.sh"
fi

cat <<EOF

Setup finished.
  Build:   ./scripts/build.sh            (debug)
           ./scripts/build.sh --release  (signed, needs --keystore)
  Install: ./scripts/build.sh --install  (phone on USB, debugging on)
  Docs:    docs/PC-SETUP.md
EOF
