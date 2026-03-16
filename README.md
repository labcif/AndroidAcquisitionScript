# Android App Data Acquisition Toolkit

A toolkit for forensic acquisition of Android app data via ADB. Available in two flavours — Bash (Linux/macOS) and Python (Linux, macOS, Windows).

Acquired data is packaged as a `.tgz` archive containing all app files plus a `sha256` manifest for integrity verification.

---

## Scripts

| Script | Bash | Python | Purpose |
|---|---|---|---|
| detect root | `detect_root.sh` | `detect_root.py` | Probe ADB connectivity and detect the available root method |
| acquisition | `acquisition.sh` | `acquisition.py` | Acquire all data files for a given app package |

---

## Requirements

- [Android SDK Platform Tools](https://developer.android.com/tools/releases/platform-tools) (`adb` in `PATH`, or set `ADB=/path/to/adb`)
- A rooted target — AVD with a `userdebug`/`eng` build, or a device rooted with [Magisk](https://github.com/topjohnwu/Magisk), LineageOS, etc.
- **Bash scripts:** Bash 4.0 or later (Linux/macOS only)
- **Python scripts:** Python 3.10 or later, standard library only — no extra packages required

---

## `detect_root`

Checks ADB connectivity and probes for the available root escalation method.

### Usage

```bash
# Bash
./detect_root.sh [-e | -d | -s <serial>]

# Python (Linux / macOS / Windows)
python detect_root.py [-e | -d | -s <serial>]
```

| Flag | Description |
|---|---|
| *(none)* | Auto-detect: tries emulator first, then USB |
| `-e` | Target emulator only |
| `-d` | Target USB device only |
| `-s <serial>` | Target a specific device by serial |

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

---

## `acquisition`

Acquires all data files for a given Android app package and saves them locally as a compressed archive.

### Usage

```bash
# Bash
./acquisition.sh <package.name> [-e|-d]

# Python (Linux / macOS / Windows)
python acquisition.py <package.name> [-e|-d]
```

| Argument | Description |
|---|---|
| `package.name` | Full or partial package name to search for |
| `-e` | Target emulator (default) |
| `-d` | Target USB device |

### Examples

```bash
python acquisition.py com.example.myapp              # emulator (default)
python acquisition.py com.example.myapp -d           # USB device
python acquisition.py myapp -e                       # partial match (errors if ambiguous)
ADB=~/sdk/platform-tools/adb python acquisition.py com.example.myapp
```

### Output

A single `.tgz` file saved in the current directory:

```
<package>-v<version>--<device><android>--<timestamp>.tgz
```

Example: `com.example.myapp-v2.4.1--emu14--2025.03.12T14.30.00.tgz`

The archive contains all acquired app files plus a `.sha256` manifest at the root.

### Integrity verification

```bash
tar -xzf com.example.myapp-v2.4.1--emu14--2025.03.12T14.30.00.tgz
sha256sum -c com.example.myapp-v2.4.1--emu14--2025.03.12T14.30.00.sha256
```

---

## Supported root environments

| Environment | Method used |
|---|---|
| AVD (`userdebug`/`eng`) | `adb root` |
| AVD with Google APIs | `su -c` |
| Magisk (physical device) | `su -c` |
| LineageOS | `su 0 -c` |
| Android ≤9 (rooted) | `su 0 cmd` |

---

## Troubleshooting

**`no emulator/device found`** — confirm `adb devices` lists the device.  
**Device shows `unauthorized`** — accept the RSA prompt on the device screen and retry.  
**`No packages found`** — use `adb shell pm list packages | grep <term>` to confirm the exact name.  
**`No data folders found`** — launch the app at least once before acquiring.  
**Pull fails or archive is empty** — check free space on `/sdcard` with `adb shell df /sdcard`.

---

## Forensic notes

- All intermediate files are removed from the device after a successful acquisition.
- The `.sha256` manifest is generated before archiving, so every file in the archive has a corresponding hash entry.
- Duplicate paths caused by bind mounts are deduplicated via inode comparison before hashing and archiving.
