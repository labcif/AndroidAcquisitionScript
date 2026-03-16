#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# acquisition.sh
# Acquires app data from an Android device/emulator via ADB.
#
# Usage:
#   ./acquisition.sh app.full.name [-d|-e]
#
# Examples:
#   ./acquisition.sh com.google.android.inputmethod.latin      # emulator
#   ./acquisition.sh com.google.android.inputmethod.latin -d   # USB device
#
# Environment:
#   ADB=/path/to/adb   override adb binary (default: auto-detected from PATH)
# ─────────────────────────────────────────────────────────────────────────────

# ── Colours ──────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    C_RESET='\033[0m'
    C_INFO='\033[0;36m'     # cyan
    C_OK='\033[0;32m'       # green
    C_WARN='\033[0;33m'     # yellow
    C_ERR='\033[0;31m'      # red
    C_BOLD='\033[1m'
    C_DIM='\033[2m'
else
    C_RESET=''; C_INFO=''; C_OK=''; C_WARN=''; C_ERR=''; C_BOLD=''; C_DIM=''
fi

log_info() { echo -e "${C_INFO}[Info ]${C_RESET} $*"; }
log_ok()   { echo -e "${C_OK}[  OK ]${C_RESET} $*"; }
log_warn() { echo -e "${C_WARN}[Warn ]${C_RESET} $*"; }
log_err()  { echo -e "${C_ERR}[Error]${C_RESET} $*"; }
log_step() { echo -e "\n${C_BOLD}── $* ${C_RESET}"; }
log_sep()  { echo -e "${C_DIM}────────────────────────────────────────${C_RESET}"; }

die() { log_err "$*"; exit 1; }

# ── Usage ─────────────────────────────────────────────────────────────────────
usage() {
    echo -e "${C_BOLD}Usage:${C_RESET}"
    echo "      $0 app.full.name [-d|-e]"
    echo ""
    echo -e "${C_BOLD}Examples:${C_RESET}"
    echo "      $0 com.google.android.inputmethod.latin       # emulator (default)"
    echo "      $0 com.google.android.inputmethod.latin -d    # USB device"
    echo ""
    echo -e "${C_BOLD}Environment:${C_RESET}"
    echo "      ADB=/path/to/adb   override adb binary"
    exit 0
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage

if [[ $# -lt 1 ]]; then
    log_err "Missing argument: app package name."
    echo ""
    usage
fi

# ── ADB validation ────────────────────────────────────────────────────────────
log_step "ADB binary check"

# Resolve ADB: honour env override, otherwise find in PATH
if [[ -n "${ADB:-}" ]]; then
    # User-supplied path — validate it directly
    if [[ ! -f "$ADB" ]]; then
        die "ADB override '$ADB' does not exist."
    fi
    if [[ ! -x "$ADB" ]]; then
        die "ADB override '$ADB' is not executable."
    fi
    log_info "Using override: $ADB"
else
    ADB=$(command -v adb 2>/dev/null) \
        || die "'adb' not found in PATH. Install Android SDK platform-tools or set ADB=/path/to/adb."
    log_info "Found in PATH: $ADB"
fi

# Confirm the binary actually runs and shows a sane version string
ADB_VERSION_LINE=$("$ADB" version 2>/dev/null | head -1)
if [[ -z "$ADB_VERSION_LINE" ]]; then
    die "'$ADB' did not produce version output — the binary may be corrupt."
fi

# Extract version number for a minimum-version check (requires >= 1.0.39)
ADB_VER=$("$ADB" version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
ADB_MAJOR=$(echo "$ADB_VER" | cut -d. -f1)
ADB_MINOR=$(echo "$ADB_VER" | cut -d. -f2)
ADB_PATCH=$(echo "$ADB_VER" | cut -d. -f3)

log_ok "$ADB_VERSION_LINE"
log_info "Version parsed: major=$ADB_MAJOR minor=$ADB_MINOR patch=$ADB_PATCH"

if [[ "$ADB_MAJOR" -lt 1 ]] || { [[ "$ADB_MAJOR" -eq 1 ]] && [[ "$ADB_MINOR" -lt 0 ]]; } || \
   { [[ "$ADB_MAJOR" -eq 1 ]] && [[ "$ADB_MINOR" -eq 0 ]] && [[ "$ADB_PATCH" -lt 39 ]]; }; then
    log_warn "ADB version $ADB_VER is older than 1.0.39 — some features may not work."
fi

# ── Arguments ─────────────────────────────────────────────────────────────────
SEARCH_TERM=$1
DEVICE=${2:--e}

log_step "Target device"
case $DEVICE in
  "-e")
    log_info "Target : emulator"
    DEVNAME="emu"
    ;;
  "-d")
    log_info "Target : USB device"
    DEVNAME="usb"
    ;;
  *)
    die "Unknown device flag \"$DEVICE\". Use -e (emulator) or -d (USB)."
    ;;
esac

# ── Connectivity check ────────────────────────────────────────────────────────
log_step "Connectivity check"

DEVICES_OUT=$("$ADB" devices 2>/dev/null | tail -n +2 | grep -v "^$")
if [[ -z "$DEVICES_OUT" ]]; then
    die "No ADB devices found. Is the device on with USB debugging enabled?"
fi

log_info "ADB device list:"
echo "$DEVICES_OUT" | while read -r line; do echo "         $line"; done

if echo "$DEVICES_OUT" | grep -q "unauthorized"; then
    log_warn "At least one device shows 'unauthorized'."
    log_warn "Accept the RSA fingerprint prompt on the device screen, then retry."
fi

PING_OUT=$("$ADB" $DEVICE shell echo "ping" 2>&1)
if [[ "$PING_OUT" != "ping" ]]; then
    die "Device ($DEVICE) did not respond. Details: $PING_OUT"
fi
log_ok "Device is reachable."

# ── Root method detection ─────────────────────────────────────────────────────
log_step "Root method detection"

ROOT_METHOD="NONE"

probe() {
    # probe <label> <shell_command>
    local label="$1" cmd="$2" result
    result=$("$ADB" $DEVICE shell "$cmd" 2>/dev/null | tr -d '\r')
    if echo "$result" | grep -q "uid=0"; then
        log_ok "Works: $label"
        return 0
    fi
    log_info "Failed: $label  (got: ${result:-<no output>})"
    return 1
}

# Method 1 — adb root (userdebug/eng AVD builds)
log_info "Trying: adb root"
ADBD_OUT=$("$ADB" $DEVICE root 2>&1 | tr -d '\r')
if ! echo "$ADBD_OUT" | grep -qE "adbd cannot run as root|error|failed"; then
    sleep 1
    if probe "adb root → id" "id"; then
        ROOT_METHOD="adb_root"
    fi
fi

# Method 2 — su -c '...'  (Android ≥10, Magisk, most AVDs)
if [[ "$ROOT_METHOD" == "NONE" ]]; then
    log_info "Trying: su -c 'cmd'"
    probe "su -c 'id'" "su -c 'id'" && ROOT_METHOD="su_c"
fi

# Method 3 — su 0 -c '...'  (LineageOS / custom ROMs)
if [[ "$ROOT_METHOD" == "NONE" ]]; then
    log_info "Trying: su 0 -c 'cmd'"
    probe "su 0 -c 'id'" "su 0 -c 'id'" && ROOT_METHOD="su_0_c"
fi

# Method 4 — su 0 cmd  (Android ≤9 / older style)
if [[ "$ROOT_METHOD" == "NONE" ]]; then
    log_info "Trying: su 0 cmd"
    probe "su 0 id" "su 0 id" && ROOT_METHOD="su_0"
fi

# Method 5 — shell already uid=0 (no su needed)
if [[ "$ROOT_METHOD" == "NONE" ]]; then
    log_info "Trying: plain shell (already root?)"
    probe "id (no su)" "id" && ROOT_METHOD="shell_root"
fi

if [[ "$ROOT_METHOD" == "NONE" ]]; then
    log_warn "No root access detected. Acquisition may be incomplete."
    log_warn "Ensure the device has a rooted build (userdebug AVD, Magisk, etc.)"
    # Not a hard exit — allow partial acquisition of non-root paths
else
    log_ok "Root method: $ROOT_METHOD"
fi

# ── Helper: run a command with root ──────────────────────────────────────────
adb_root_shell() {
    local CMD_STR="$1"
    case "$ROOT_METHOD" in
        "adb_root"|"shell_root")
            "$ADB" $DEVICE shell "$CMD_STR"
            ;;
        "su_c")
            "$ADB" $DEVICE shell "su -c '$CMD_STR'"
            ;;
        "su_0_c")
            "$ADB" $DEVICE shell "su 0 -c '$CMD_STR'"
            ;;
        "su_0")
            "$ADB" $DEVICE shell "su 0 $CMD_STR"
            ;;
        "NONE")
            "$ADB" $DEVICE shell "$CMD_STR"
            ;;
    esac
}

# ── Android version ───────────────────────────────────────────────────────────
log_step "Device info"
ANDROID_VERSION=$("$ADB" $DEVICE shell getprop ro.build.version.release | tr -d '\r')
ANDROID=$(echo "$ANDROID_VERSION" | cut -d'.' -f1)
DEVICE_MODEL=$("$ADB" $DEVICE shell getprop ro.product.model 2>/dev/null | tr -d '\r')
DEVICE_BRAND=$("$ADB" $DEVICE shell getprop ro.product.brand 2>/dev/null | tr -d '\r')
log_info "Device  : $DEVICE_BRAND $DEVICE_MODEL"
log_info "Android : $ANDROID_VERSION"

# ── Package lookup ────────────────────────────────────────────────────────────
log_step "Package lookup"
log_info "Searching for: \"$SEARCH_TERM\""

MATCHES=$("$ADB" $DEVICE shell pm list packages | grep "$SEARCH_TERM" | cut -d: -f2 | tr -d '\r')
MATCH_COUNT=$(echo "$MATCHES" | grep -c .)

if [[ -z "$MATCHES" ]]; then
    die "No packages found matching \"$SEARCH_TERM\"."
fi

if [[ "$MATCH_COUNT" -ge 2 ]]; then
    log_warn "$MATCH_COUNT matches found — please narrow down the search term:"
    echo "$MATCHES" | while read -r pkg; do echo "         $pkg"; done
    die "Ambiguous match. Exiting."
fi

APP=$MATCHES
log_ok "Package: $APP"

# ── Version & filename ────────────────────────────────────────────────────────
log_step "Acquisition"
VERSION=$("$ADB" $DEVICE shell dumpsys package "$APP" | grep versionName | cut -d= -f2 | tr -d '\r')
FILENAME="${APP}-v${VERSION}--${DEVNAME}${ANDROID}--$(date '+%Y.%m.%dT%H.%M.%S')"
log_info "Version  : $VERSION"
log_info "Filename : $FILENAME"

# ── Find app folders ──────────────────────────────────────────────────────────
log_info "Searching for app data folders..."

SEARCH_FOLDERS=(
    "/data_mirror/data_ce/"
    "/data/media/"
    "/data/user_de/"
    "/data/user/"
    "/storage/emulated/"
)

declare -A seen_inodes
FOUND_FOLDERS=()

for FOLDER in "${SEARCH_FOLDERS[@]}"; do
    while IFS= read -r FOLDER_RESULT; do
        FOLDER_RESULT=$(echo "$FOLDER_RESULT" | tr -d '\r')
        [[ -n "$FOLDER_RESULT" ]] && FOUND_FOLDERS+=("$FOLDER_RESULT")
    done < <(adb_root_shell "find $FOLDER -type d -name $APP 2>/dev/null")
done

if [[ ${#FOUND_FOLDERS[@]} -eq 0 ]]; then
    die "No data folders found for \"$APP\". Is the app installed and has it been run?"
fi

log_sep
for FOLDER in "${FOUND_FOLDERS[@]}"; do
    INODE=$(adb_root_shell "stat -c %i '$FOLDER'" | tr -d '\r')
    if [[ -n "$INODE" && -z "${seen_inodes[$INODE]}" ]]; then
        log_info "Adding : $FOLDER"
        seen_inodes[$INODE]=1
        adb_root_shell "find '$FOLDER' -print0 >> /sdcard/Download/$FILENAME.txt"
    else
        log_info "Skipped (duplicate inode $INODE): $FOLDER"
    fi
done
log_sep

# ── SHA256 checksums ──────────────────────────────────────────────────────────
# Generated on the device before archiving so all files are known.
# Only regular files are hashed (sha256sum errors on dirs/sockets/pipes).
# Paths are stripped of the leading "/" → relative paths → so that after
# extracting the archive you can verify with just:  sha256sum -c sha256.txt
#
# Android toybox sha256sum output format: "<hash>  <path>"  (two spaces)
# That is exactly the format sha256sum -c expects — no post-processing needed
# beyond removing the leading slash.
log_info "Generating SHA256 checksums..."

adb_root_shell "
cat /sdcard/Download/$FILENAME.txt \
  | xargs -0 sh -c 'for f; do [ -f \"\$f\" ] && printf \"%s\\0\" \"\$f\"; done' _ \
  | xargs -0 sha256sum 2>/dev/null \
  | sed 's|  /|  |' \
  > /sdcard/Download/${FILENAME}.sha256
"

SHA256_COUNT=$(adb_root_shell "wc -l < /sdcard/Download/${FILENAME}-sha256.txt" | tr -d '\r ')
log_ok "Checksums computed: ${SHA256_COUNT} file(s)"

# ── Compress ──────────────────────────────────────────────────────────────────
# Append the sha256 file path (null-terminated) to the existing file list so
# that a single tar pass produces the final .tgz.
# The sha256 file is stored at the archive root as "$FILENAME.sha256".
log_info "Compressing..."

adb_root_shell "cat /sdcard/Download/$FILENAME.txt | xargs -0 tar -czf /sdcard/Download/$FILENAME.tgz -C /sdcard/Download $FILENAME.sha256"

log_ok "Compression done — $FILENAME.sha256 included in archive."

# ── Pull to local ─────────────────────────────────────────────────────────────
log_info "Copying to local storage..."
"$ADB" $DEVICE pull /sdcard/Download/$FILENAME.tgz . \
    && log_ok "Saved: ./$FILENAME.tgz" \
    || die "Pull failed. Check available disk space."

# ── Cleanup ───────────────────────────────────────────────────────────────────
log_info "Cleaning up device..."
"$ADB" $DEVICE shell rm /sdcard/Download/$FILENAME.tgz
"$ADB" $DEVICE shell rm /sdcard/Download/$FILENAME.txt
"$ADB" $DEVICE shell rm /sdcard/Download/${FILENAME}-sha256.txt
log_ok "Device cleanup done."

log_sep
log_ok "Acquisition complete: ${C_BOLD}./$FILENAME.tgz${C_RESET}"
log_info "To verify integrity after extraction:"
echo -e "         ${C_BOLD}tar -xzf $FILENAME.tgz${C_RESET}"
echo -e "         ${C_BOLD}sha256sum -c sha256.txt${C_RESET}"
log_sep
