<div align="center">

<img src="Logo.svg" width="120" alt="Bluke Free logo" />

# Bluke Free

Use your Android phone as a Bluetooth keyboard, touchpad, gamepad and media remote —
no companion app or server on the host side.

[![Build APK](https://github.com/alif-primary/Bluke/actions/workflows/build.yml/badge.svg)](https://github.com/alif-primary/Bluke/actions/workflows/build.yml)
[![Latest release](https://img.shields.io/github/v/release/alif-primary/Bluke?color=orange)](https://github.com/alif-primary/Bluke/releases)
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](LICENSE)

</div>

---

## This is a fork

**Bluke Free** is a rebranded community fork of
[**Bluke**](https://github.com/arnav-kr/Bluke) by [arnav-kr](https://github.com/arnav-kr),
distributed under the same **GNU AGPL-3.0** license. The upstream project is already free
software; this fork exists to ship an independently built APK under its own application ID so
it can be installed next to (or instead of) upstream, and to document a fully automated,
self-hosted build.

Modifications relative to upstream (`v1.1.0`):

| Change | Where |
| --- | --- |
| Application ID `dev.arnv.bluke` → `io.github.alifprimary.blukefree` (installs side-by-side) | `app/build.gradle.kts` |
| Display name and Bluetooth HID device name → `Bluke Free` | `strings.xml`, `BluetoothKeyboardManager.kt` |
| About screen links and "Free software fork" notice point at this repo | `AboutActivity.kt` |
| CI rewritten: debug-or-signed build, artifact upload, tag → GitHub Release | `.github/workflows/build.yml` |

Everything else — HID descriptors, layouts, themes, sound packs — is upstream work. Per AGPL-3.0
§5, the complete corresponding source of this fork is this repository.

## Download

Grab `bluke-free-<version>-debug.apk` (or `-release.apk` when signed) from the
[**Releases**](https://github.com/alif-primary/Bluke/releases) page, or from the latest
[Actions run](https://github.com/alif-primary/Bluke/actions/workflows/build.yml) artifacts.
Sideload it — the Play Store is not involved.

## Features

- Direct Bluetooth HID connection — no host-side software, works with Windows, Linux, Android, ChromeOS
- Four input modes: **Keyboard**, **Touchpad**, **Gamepad**, **Multimedia remote**
- Mechanical switch sound profiles (12 built-in) plus importable Mechvibes sound packs
- Layouts: QWERTY, AZERTY, QWERTZ, Dvorak, Colemak, Russian ЙЦУКЕН (`Shift + Space` to cycle)
- 60% / 65% / 75% keyboard geometries, custom themes, Material You theming, OLED black, haptics

Usage and troubleshooting: [docs/USAGE.md](docs/USAGE.md).

## Requirements

- **Android 9 (API 28) or newer** with firmware that exposes the **Bluetooth HID Device profile**.
  This is a firmware capability, not something an app can add — if your ROM lacks it, no HID app
  will work on that device.
- A host that accepts generic Bluetooth HID: Windows, Linux, Android/Android TV, ChromeOS.
  Apple/macOS hosts are not supported upstream.

## Build

### On a PC (one command)

Windows:

```powershell
.\scripts\setup.ps1              # installs JDK 17 + Android SDK, then builds
.\scripts\build.ps1 -Install     # rebuild + install over USB
```

Linux / macOS:

```bash
./scripts/setup.sh               # installs JDK 17 + Android SDK, then builds
./scripts/build.sh --install     # rebuild + install over USB
```

The SDK is installed into user space (`%LOCALAPPDATA%\Android\Sdk`, `~/Android/Sdk`)
and `local.properties` is written for you. Full details and troubleshooting:
[docs/PC-SETUP.md](docs/PC-SETUP.md).

Already have Android Studio and an SDK? Skip the setup script:

```bash
./gradlew assembleDebug      # app/build/outputs/apk/debug/app-debug.apk
./gradlew installDebug       # to a USB-connected device
```

### CI build

`.github/workflows/build.yml` runs on every push to `main`, every PR, and on `v*` tags:

- builds `assembleDebug` by default and uploads the APK as the `apk` artifact;
- builds `assembleRelease` instead **if** signing secrets exist;
- on a `v*` tag, attaches the APK to a GitHub Release.

To enable signed release builds, add these repository secrets (`Settings → Secrets and variables → Actions`):

| Secret | Contents |
| --- | --- |
| `KEYSTORE_BASE64` | `base64 -w0 my-upload-key.jks` |
| `KEYSTORE_PASSWORD` | keystore password |
| `KEY_ALIAS` | key alias (upstream default: `k0`) |
| `KEY_PASSWORD` | key password |

Creating the keystore (one-off, on any machine with a JDK):

```bash
keytool -genkeypair -v -keystore my-upload-key.jks -alias k0 \
  -keyalg RSA -keysize 4096 -validity 10000
base64 -w0 my-upload-key.jks | gh secret set KEYSTORE_BASE64 -R alif-primary/Bluke
```

## License

[GNU Affero General Public License v3.0](LICENSE). Original work © the Bluke contributors;
modifications in this fork are released under the same license.

## Credits

- [arnav-kr/Bluke](https://github.com/arnav-kr/Bluke) — upstream project
- [kbs.im](https://kbs.im) / [kbsim](https://github.com/tplai/kbsim) — mechanical switch audio assets
- [Atharok/BtRemote](https://gitlab.com/Atharok/BtRemote) — lineage of the serverless HID approach
