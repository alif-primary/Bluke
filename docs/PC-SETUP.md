# Building Bluke Free on a PC

Two commands, no Android Studio required. The scripts install a JDK 17 and the
Android command-line tools into user space, accept the SDK licences, write
`local.properties`, and build.

## Windows (PowerShell)

```powershell
git clone https://github.com/alif-primary/Bluke.git
cd Bluke
.\scripts\setup.ps1
```

That is it. The APK lands in `app\build\outputs\apk\debug\`.

| Task | Command |
| --- | --- |
| Rebuild | `.\scripts\build.ps1` |
| Install over USB | `.\scripts\build.ps1 -Install` |
| Signed release | `.\scripts\build.ps1 -Release -Keystore C:\keys\my-upload-key.jks` |
| Update the repo | `.\scripts\sync.ps1 "describe change"` |

If PowerShell blocks the scripts:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

## Linux (and macOS)

```bash
git clone https://github.com/alif-primary/Bluke.git
cd Bluke
./scripts/setup.sh
```

| Task | Command |
| --- | --- |
| Rebuild | `./scripts/build.sh` |
| Install over USB | `./scripts/build.sh --install` |
| Signed release | `./scripts/build.sh --release --keystore ~/keys/my-upload-key.jks` |
| Update the repo | `./scripts/sync.sh "describe change"` |

`setup.sh` needs `sudo` for the JDK on Linux. On macOS it uses Homebrew
(`brew install openjdk@17`).

## What the setup script actually does

1. Finds a JDK ≥ 17 (installs one if missing) and sets `JAVA_HOME`.
2. Downloads the newest `commandlinetools` build from
   `dl.google.com/android/repository/repository2-3.xml` (falls back to a pinned
   build if the index cannot be read).
3. Installs the SDK into `%LOCALAPPDATA%\Android\Sdk` / `~/Android/Sdk`
   (override with `-SdkRoot` / `--sdk-root`).
4. Accepts licences and installs `platform-tools`, `platforms;android-36.1`,
   `build-tools;36.1.0`. Anything else Gradle fetches on the first build.
5. Writes `local.properties` (`local.properties` is git-ignored — never commit it).
6. Runs a debug build.

Nothing is written outside the SDK directory, the JDK install, and the user
environment variables `JAVA_HOME` / `ANDROID_HOME`.

## No SDK at all? Use CI

The GitHub Actions workflow builds the same project on every push:

```bash
gh workflow run build.yml -R alif-primary/Bluke
gh run watch -R alif-primary/Bluke
gh release download -R alif-primary/Bluke --dir ~/apk-archive
```

Pushing a `v*` tag publishes a signed release automatically. This is the path to
use from a phone (Termux) — `setup.sh` detects Termux and refuses to install a
2–3 GB SDK there.

## Signed release builds

Release builds are only signed when a keystore is supplied. Local:

```bash
./scripts/build.sh --release --keystore ~/keys/my-upload-key.jks
```

Gradle reads `KEYSTORE_PATH`, `STORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` from
the environment, which is what the scripts set and what the workflow uses.

In CI they come from repository secrets — see the README table
(`KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`).

Keep the keystore backed up: installs signed with a lost key can never be
updated, only uninstalled and replaced.

## Android Studio instead

Open the repository folder as a project. Studio will offer to install the SDK
components it needs; accept, then press Run. `applicationId` is
`io.github.alifprimary.blukefree`, so it installs alongside upstream Bluke.

## Installing the APK on the phone

```bash
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

or copy the `.apk` to the phone and tap it (allow "install unknown apps" for the
file manager first).

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `JAVA_HOME is not set` / `Unsupported class file major version` | A pre-17 JDK is winning. `setup.ps1` sets `JAVA_HOME` for the session; open a new terminal after the first run. |
| `SDK location not found` | `local.properties` missing. Re-run setup, or set `ANDROID_HOME`. |
| `Failed to install the following SDK components ... licences not accepted` | Re-run setup (it pipes `y` into `sdkmanager --licenses`). |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | The phone has a build signed with a different key (e.g. the old debug APK). Uninstall `Bluke Free`, then install again. |
| `INSTALL_FAILED_VERSION_DOWNGRADE` | Installed build has a higher `versionCode`. Bump it in `app/build.gradle.kts`. |
| Build works, phone never sees the device | The ROM does not expose the Bluetooth **HID Device** profile. Firmware limitation — no app can work around it. |
| `Could not resolve ...` on first build | Corporate proxy/VPN. Gradle needs `dl.google.com` and `repo.maven.apache.org`. |
| Termux: `setup.sh` exits immediately | Intentional. Build on the PC or via Actions; a local SDK is 2–3 GB. |

## Keeping the fork in sync

`.github/workflows/upstream-sync.yml` runs every Monday and on demand. It merges
`arnav-kr/Bluke:main` into this fork and opens a pull request when upstream has
new commits. Conflicts fail the run loudly instead of half-merging.

Locally, the manual equivalent:

```bash
git fetch upstream
git merge upstream/main
```

Conflicts almost always land in the four rebranded files: `app/build.gradle.kts`,
`strings.xml`, `BluetoothKeyboardManager.kt`, `AboutActivity.kt`.
