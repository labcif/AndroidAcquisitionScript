#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# detect_root.sh
# Detects ADB connectivity and available root method on an Android device.
#
# Usage:
#   ./detect_root.sh           # auto-detect (emulator first, then USB)
#   ./detect_root.sh -e        # emulator only
#   ./detect_root.sh -d        # USB device only
#   ./detect_root.sh -s <id>   # specific device serial
# ─────────────────────────────────────────────────────────────────────────────

ADB="${ADB:-adb}"   # override with ADB=/path/to/adb ./detect_root.sh if needed

# ── Colours ──────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then   # only use colours when output is a terminal
    C_RESET='\033[0m'
    C_INFO='\033[0;36m'    # cyan
    C_OK='\033[0;32m'      # green
    C_WARN='\033[0;33m'    # yellow
    C_ERR='\033[0;31m'     # red
    C_BOLD='\033[1m'
else
    C_RESET=''; C_INFO=''; C_OK=''; C_WARN=''; C_ERR=''; C_BOLD=''
fi


log_info() { echo -e "${C_INFO}[Info ]${C_RESET} $*"; }
log_ok()   { echo -e "${C_OK}[  OK ]${C_RESET} $*"; }
log_warn() { echo -e "${C_WARN}[Warn ]${C_RESET} $*"; }
log_err()  { echo -e "${C_ERR}[Error]${C_RESET} $*"; }
log_step() { echo -e "\n${C_BOLD}── $* ${C_RESET}"; }

# ── Usage ─────────────────────────────────────────────────────────────────────
usage() {
    echo "Usage: $0 [-e | -d | -s <serial>]"
    echo ""
    echo "  (no flag)      auto-detect: try emulator, then USB"
    echo "  -e             target emulator"
    echo "  -d             target USB device"
    echo "  -s <serial>    target specific device by serial"
    echo ""
    echo "Environment:"
    echo "  ADB=/path/to/adb  override adb binary (default: adb from PATH)"
    exit 0
}

# ── Argument parsing ──────────────────────────────────────────────────────────
DEVICE_FLAG=""
AUTO_DETECT=false

case "${1:-}" in
    -h|--help) usage ;;
    -e)        DEVICE_FLAG="-e" ;;
    -d)        DEVICE_FLAG="-d" ;;
    -s)
        [[ -z "${2:-}" ]] && { log_err "'-s' requires a serial number."; exit 1; }
        DEVICE_FLAG="-s $2"
        ;;
    "")        AUTO_DETECT=true ;;
    *)         log_err "Unknown option: $1"; usage ;;
esac

# ── Sanity check: adb available ───────────────────────────────────────────────
log_step "ADB binary check"
if ! command -v "$ADB" &>/dev/null; then
    log_err "'$ADB' not found. Install Android SDK platform-tools or set ADB=/path/to/adb."
    exit 1
fi
ADB_VERSION=$("$ADB" version 2>/dev/null | head -1)
log_ok "Found: $ADB_VERSION"
log_ok "Path: $(which $ADB)"

# ── Helper: run adb with the chosen device flag ───────────────────────────────
adb_run() {
    # shellcheck disable=SC2086
    "$ADB" $DEVICE_FLAG "$@" 2>/dev/null
}

# ── Step 1: connectivity ──────────────────────────────────────────────────────
check_connectivity() {
    local target_label="$1"

    log_step "Connectivity check: $target_label"

    # Confirm at least one device is visible in adb devices
    local devices
    devices=$("$ADB" devices 2>/dev/null | tail -n +2 | grep -v "^$")

    if [[ -z "$devices" ]]; then
        log_err "No ADB devices found at all. Is the device on and USB debugging enabled?"
        return 1
    fi

    log_info "ADB device list:"
    echo "$devices" | while read -r line; do echo "         $line"; done

    # Check for 'unauthorized'
    if echo "$devices" | grep -q "unauthorized"; then
        log_warn "At least one device is 'unauthorized'."
        log_warn "Accept the RSA fingerprint prompt on the device screen."
    fi

    # Attempt a simple shell command to confirm the chosen target responds
    local test_out
    test_out=$(adb_run shell echo "ping" 2>&1)

    if [[ "$test_out" == *"error"* ]] || [[ "$test_out" == *"failed"* ]] || [[ -z "$test_out" ]]; then
        log_err "Device flag '$DEVICE_FLAG' did not respond. Details: $test_out"
        return 1
    fi

    # Grab serial and device info
    DEVICE_SERIAL=$(adb_run get-serialno 2>/dev/null)
    DEVICE_MODEL=$(adb_run shell getprop ro.product.model 2>/dev/null | tr -d '\r')
    DEVICE_BRAND=$(adb_run shell getprop ro.product.brand 2>/dev/null | tr -d '\r')
    ANDROID_VERSION=$(adb_run shell getprop ro.build.version.release 2>/dev/null | tr -d '\r')
    ANDROID_SDK=$(adb_run shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r')
    BUILD_TYPE=$(adb_run shell getprop ro.build.type 2>/dev/null | tr -d '\r')

    log_ok "Device reachable!"
    log_info "Serial  : ${DEVICE_SERIAL:-unknown}"
    log_info "Device  : $DEVICE_BRAND $DEVICE_MODEL"
    log_info "Android : $ANDROID_VERSION  (SDK $ANDROID_SDK)"
    log_info "Build   : $BUILD_TYPE"
    return 0
}

# ── Auto-detect: try emulator, then USB ───────────────────────────────────────
if $AUTO_DETECT; then
    log_info "No device flag given — auto-detecting..."

    DEVICE_FLAG="-e"
    if check_connectivity "emulator"; then
        log_ok "Using emulator."
    else
        log_warn "No emulator found. Trying USB device..."
        DEVICE_FLAG="-d"
        if check_connectivity "USB device"; then
            log_ok "Using USB device."
        else
            log_err "No reachable device found (emulator or USB)."
            log_err "Run 'adb devices' to inspect the current state."
            exit 1
        fi
    fi
else
    check_connectivity "$DEVICE_FLAG" || exit 1
fi

# ── Step 2: root method detection ─────────────────────────────────────────────
log_step "Root method detection"

ROOT_METHOD="none"
ROOT_LABEL="No root access detected"

# Probe function: runs a command and checks if uid=0 is returned
probe() {
    local method_label="$1"
    local shell_cmd="$2"
    local result
    result=$("$ADB" $DEVICE_FLAG shell "$shell_cmd" 2>/dev/null | tr -d '\r')
    if echo "$result" | grep -q "uid=0"; then
        log_ok "Method works: $method_label"
        return 0
    fi
    log_info "Method failed: $method_label  (got: ${result:-<no output>})"
    return 1
}

# ── Method 1: adb root (restarts adbd as root — needs userdebug/eng build) ───
log_info "Trying: adb root  (restarts adbd — requires userdebug/eng build)"
ADBD_ROOT_OUT=$("$ADB" $DEVICE_FLAG root 2>&1 | tr -d '\r')

if ! echo "$ADBD_ROOT_OUT" | grep -q "adbd cannot run as root\|error\|failed"; then
    sleep 1   # give adbd time to restart
    if probe "adb root → plain shell id" "id"; then
        ROOT_METHOD="adb_root"
        ROOT_LABEL="adb root  (adbd restarted as root — plain shell commands work directly)"
    fi
fi

# ── Method 2: su -c '...' ─────────────────────────────────────────────────────
if [[ "$ROOT_METHOD" == "none" ]]; then
    log_info "Trying: su -c 'cmd'  (Android ≥10, Magisk, most AVDs)"
    if probe "su -c 'id'" "su -c 'id'"; then
        ROOT_METHOD="su_c"
        ROOT_LABEL="su -c 'cmd'  (Android ≥10 / Magisk style)"
    fi
fi

# ── Method 3: su 0 -c '...' ──────────────────────────────────────────────────
if [[ "$ROOT_METHOD" == "none" ]]; then
    log_info "Trying: su 0 -c 'cmd'  (LineageOS / some custom ROMs)"
    if probe "su 0 -c 'id'" "su 0 -c 'id'"; then
        ROOT_METHOD="su_0_c"
        ROOT_LABEL="su 0 -c 'cmd'  (LineageOS / custom ROM style)"
    fi
fi

# ── Method 4: su 0 cmd (no -c, space-separated) ──────────────────────────────
if [[ "$ROOT_METHOD" == "none" ]]; then
    log_info "Trying: su 0 cmd  (Android ≤9 / older ROMs)"
    if probe "su 0 id" "su 0 id"; then
        ROOT_METHOD="su_0"
        ROOT_LABEL="su 0 cmd  (Android ≤9 / older ROM style)"
    fi
fi

# ── Method 5: already root (adb shell is uid=0 without su) ───────────────────
if [[ "$ROOT_METHOD" == "none" ]]; then
    log_info "Trying: plain shell — checking if already uid=0"
    if probe "plain shell id (already root?)" "id"; then
        ROOT_METHOD="shell_root"
        ROOT_LABEL="plain shell already runs as root (no su needed)"
    fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
log_step "Result"

if [[ "$ROOT_METHOD" == "none" ]]; then
    log_warn "Root method : NONE"
    log_warn "No root access could be obtained on this device."
    log_warn "Ensure the device has a rooted build (userdebug/eng AVD, Magisk, etc.)"
    EXIT_CODE=2
else
    log_ok  "Root method : $ROOT_METHOD"
    log_info "Description : $ROOT_LABEL"
    log_info ""
    log_info "To use in your scripts, call root commands as follows:"
    echo ""
    case "$ROOT_METHOD" in
        "adb_root")
            echo -e "    ${C_BOLD}adb $DEVICE_FLAG shell 'your_command_here'${C_RESET}"
            echo -e "    ${C_INFO}(adbd already runs as root — no su wrapper needed)${C_RESET}"
            ;;
        "su_c")
            echo -e "    ${C_BOLD}adb $DEVICE_FLAG shell \"su -c 'your_command_here'\"${C_RESET}"
            ;;
        "su_0_c")
            echo -e "    ${C_BOLD}adb $DEVICE_FLAG shell \"su 0 -c 'your_command_here'\"${C_RESET}"
            ;;
        "su_0")
            echo -e "    ${C_BOLD}adb $DEVICE_FLAG shell 'su 0 your_command_here'${C_RESET}"
            ;;
        "shell_root")
            echo -e "    ${C_BOLD}adb $DEVICE_FLAG shell 'your_command_here'${C_RESET}"
            echo -e "    ${C_INFO}(shell user is already uid=0)${C_RESET}"
            ;;
    esac
    echo ""
    EXIT_CODE=0
fi

echo ""
echo -e "${C_BOLD}ROOT_METHOD=$ROOT_METHOD${C_RESET}"   # machine-readable last line
exit $EXIT_CODE
