# Android App Data Acquisition Toolkit

A pair of Bash scripts for forensic acquisition of Android app data via ADB. Designed for use with emulators (AVD) and physical devices over USB.

Acquired data is packaged as a `.tgz` archive containing all app files plus a `sha256` manifest for integrity verification.

---

## Scripts

| Script | Purpose |
|---|---|
| `detect_root.sh` | Probe ADB connectivity and detect the available root method |
| `acquisition.sh` | Acquire all data files for a given app package |

---

## Requirements

- [Android SDK Platform Tools](https://developer.android.com/tools/releases/platform-tools) (`adb` in `PATH`, or set `ADB=/path/to/adb`)
- A rooted target — AVD with a `userdebug`/`eng` build, or a device rooted with [Magisk](https://github.com/topjohnwu/Magisk), LineageOS, etc.
- Bash 4.0 or later
- Standard Unix tools: `grep`, `sed`, `cut`, `date`

---

## `detect_root.sh`

Checks ADB connectivity and probes for the available root escalation method. Useful before running an acquisition to confirm the environment is ready.

### Usage

```bash
./detect_root.sh                  # auto-detect: tries emulator first, then USB
./detect_root.sh -e               # target emulator only
./detect_root.sh -d               # target USB device only
./detect_root.sh -s emulator-5554 # target a specific device by serial
```

### Root methods probed (in order)

| Priority | Method | Typical environment |
|---|---|---|
| 1 | `adb root` | AVD `userdebug`/`eng` builds |
| 2 | `su -c 'cmd'` | Android ≥10, Magisk |
| 3 | `su 0 -c 'cmd'` | LineageOS, custom ROMs |
| 4 | `su 0 cmd` | Android ≤9, older ROMs |
| 5 | plain shell (already uid=0) | Special builds |

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Root method found |
| `1` | No ADB connectivity |
| `2` | Connected but no root access |

### Example output

```
── ADB binary check
[  OK ] Found: Android Debug Bridge version 35.0.2
[Info ] Found in PATH: /usr/local/bin/adb

── Connectivity check — emulator
[Info ] ADB device list:
         emulator-5554   device
[  OK ] Device reachable!
[Info ] Serial  : emulator-5554
[Info ] Device  : Google sdk_gphone64_x86_64
[Info ] Android : 14  (SDK 34)
[Info ] Build   : userdebug

── Root method detection
[Info ] Trying: adb root
[  OK ] Works: adb root → id
[  OK ] Root method: adb_root

── Result
[  OK ] Root method : adb_root
[Info ] Description : adb root  (adbd restarted as root — plain shell commands work directly)

ROOT_METHOD=adb_root
```

---

## `acquisition.sh`

Acquires all data files for a given Android app package and saves them locally as a compressed archive.

### Usage

```bash
./acquisition.sh <package.name> [-e|-d]
```

| Argument | Description |
|---|---|
| `package.name` | Full or partial package name to search for |
| `-e` | Target emulator (default) |
| `-d` | Target USB device |

### Environment variables

```bash
ADB=/path/to/adb ./acquisition.sh com.example.app   # use a custom adb binary
```

### Examples

```bash
# Acquire from the running emulator (default)
./acquisition.sh com.example.myapp

# Acquire from a USB-connected device
./acquisition.sh com.example.myapp -d

# Partial name match (will error if more than one package matches)
./acquisition.sh myapp -e

# Use a custom adb binary
ADB=~/Library/Android/sdk/platform-tools/adb ./acquisition.sh com.example.myapp
```

### What it acquires

The script searches the following locations on the device:

```
/data_mirror/data_ce/
/data/media/
/data/user_de/
/data/user/
/storage/emulated/
```

Duplicate paths (same inode, e.g. bind mounts) are detected and skipped automatically.

### Output

A single `.tgz` file is saved in the current directory:

```
<package>-v<version>--<device><android>--<timestamp>.tgz
```

For example:

```
com.example.myapp-v2.4.1--emu14--2025.03.12T14.30.00.tgz
```

The archive contains all acquired app files plus a `.sha256` manifest at the root:

```
data/user/0/com.example.myapp/databases/main.db
data/user/0/com.example.myapp/shared_prefs/settings.xml
data/user/0/com.example.myapp/files/cache.json
...
com.example.myapp-v2.4.1--emu14--2025.03.12T14.30.00.sha256
```

### Integrity verification

After extraction, verify all files against the manifest:

```bash
tar -xzf com.example.myapp-v2.4.1--emu14--2025.03.12T14.30.00.tgz
sha256sum -c com.example.myapp-v2.4.1--emu14--2025.03.12T14.30.00.sha256
```

Expected output:

```
data/user/0/com.example.myapp/databases/main.db: OK
data/user/0/com.example.myapp/shared_prefs/settings.xml: OK
...
```

---

## Supported root environments

| Environment | Method used | Notes |
|---|---|---|
| AVD (`userdebug`/`eng`) | `adb root` | Most reliable; no `su` binary needed |
| AVD with Google APIs | `su -c` | `adb root` is blocked on Google API images |
| Magisk (physical device) | `su -c` | Requires Magisk installed and root granted to shell |
| LineageOS | `su 0 -c` | Tested on LineageOS 20+ |
| Android ≤9 (rooted) | `su 0 cmd` | Older `su` syntax without `-c` flag |

---

## Troubleshooting

**`adb: error: no emulator/device found`**
Start the emulator or connect the device and confirm `adb devices` lists it.

**Device shows `unauthorized`**
Accept the RSA key fingerprint prompt on the device screen, then run the script again.

**`No packages found matching "..."`**
Use `adb shell pm list packages | grep <term>` to confirm the exact package name.

**`No data folders found`**
The app may not have been launched yet — some apps only create their data directories on first run.

**Archive is empty or pull fails**
Check available storage on `/sdcard` with `adb shell df /sdcard`. The intermediate files (file list + uncompressed hashes) require space proportional to the app data size.

---

## Notes on forensic use

- All intermediate files (`*.txt`, `*.sha256`) are removed from the device after a successful acquisition.
- The `.sha256` manifest is generated **before** archiving, from the same file list used by `tar`, so every file in the archive has a corresponding hash entry.
- Duplicate paths caused by bind mounts (common in Android's multi-user storage layout) are deduplicated via inode comparison before hashing and archiving.
