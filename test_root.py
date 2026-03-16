#!/usr/bin/env python3
"""
detect_root.py
Detects ADB connectivity and available root method on an Android device.

Usage:
    python detect_root.py                # auto-detect (emulator first, then USB)
    python detect_root.py -e             # emulator only
    python detect_root.py -d             # USB device only
    python detect_root.py -s <serial>    # specific device serial

Environment:
    ADB=/path/to/adb   override adb binary (default: auto-detected from PATH)
"""

import argparse
import os
import shutil
import subprocess
import sys
import time


# ── Colours ───────────────────────────────────────────────────────────────────
def _supports_colour() -> bool:
    if sys.platform == "win32":
        try:
            import ctypes
            kernel32 = ctypes.windll.kernel32          # type: ignore[attr-defined]
            kernel32.SetConsoleMode(kernel32.GetStdHandle(-11), 7)
            return True
        except Exception:
            return False
    return hasattr(sys.stdout, "isatty") and sys.stdout.isatty()


USE_COLOUR = _supports_colour()

C_RESET = "\033[0m"    if USE_COLOUR else ""
C_INFO  = "\033[0;36m" if USE_COLOUR else ""
C_OK    = "\033[0;32m" if USE_COLOUR else ""
C_WARN  = "\033[0;33m" if USE_COLOUR else ""
C_ERR   = "\033[0;31m" if USE_COLOUR else ""
C_BOLD  = "\033[1m"    if USE_COLOUR else ""


def log_info(msg: str) -> None:
    print(f"{C_INFO}[Info ]{C_RESET} {msg}")

def log_ok(msg: str) -> None:
    print(f"{C_OK}[  OK ]{C_RESET} {msg}")

def log_warn(msg: str) -> None:
    print(f"{C_WARN}[Warn ]{C_RESET} {msg}")

def log_err(msg: str) -> None:
    print(f"{C_ERR}[Error]{C_RESET} {msg}", file=sys.stderr)

def log_step(msg: str) -> None:
    print(f"\n{C_BOLD}── {msg} {C_RESET}")


# ── ADB helpers ───────────────────────────────────────────────────────────────
def run(cmd: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)


def adb_run(adb: str, device_args: list[str], *args: str) -> subprocess.CompletedProcess:
    """Run an adb command with the chosen device flags."""
    return run([adb] + device_args + list(args))


def adb_shell(adb: str, device_args: list[str], cmd: str) -> str:
    result = adb_run(adb, device_args, "shell", cmd)
    return result.stdout.replace("\r", "").strip()


# ── ADB binary check ──────────────────────────────────────────────────────────
def resolve_adb() -> str:
    log_step("ADB binary check")

    adb_env = os.environ.get("ADB", "")
    if adb_env:
        if not os.path.isfile(adb_env):
            log_err(f"ADB override '{adb_env}' does not exist.")
            sys.exit(1)
        if not os.access(adb_env, os.X_OK):
            log_err(f"ADB override '{adb_env}' is not executable.")
            sys.exit(1)
        adb = adb_env
    else:
        adb = shutil.which("adb") or ""
        if not adb:
            log_err("'adb' not found. Install Android SDK platform-tools or set ADB=/path/to/adb.")
            sys.exit(1)

    version_out = run([adb, "version"])
    first_line = version_out.stdout.splitlines()[0] if version_out.stdout else ""
    log_ok(f"Found: {first_line}")
    log_ok(f"Path: {adb}")
    return adb


# ── Connectivity check ────────────────────────────────────────────────────────
def check_connectivity(adb: str, device_args: list[str], label: str) -> dict | None:
    """
    Check that the chosen device is reachable.
    Returns a dict with device info on success, None on failure.
    """
    log_step(f"Connectivity check: {label}")

    devices_out = run([adb, "devices"])
    lines = [l for l in devices_out.stdout.splitlines()[1:] if l.strip()]
    if not lines:
        log_err("No ADB devices found at all. Is the device on and USB debugging enabled?")
        return None

    log_info("ADB device list:")
    for line in lines:
        print(f"         {line}")

    if any("unauthorized" in line for line in lines):
        log_warn("At least one device is 'unauthorized'.")
        log_warn("Accept the RSA fingerprint prompt on the device screen.")

    # Confirm chosen target responds
    ping_result = adb_run(adb, device_args, "shell", "echo ping")
    ping_out = (ping_result.stdout + ping_result.stderr).replace("\r", "").strip()
    if "error" in ping_out.lower() or "failed" in ping_out.lower() or not ping_out:
        log_err(f"Device flag '{' '.join(device_args)}' did not respond. Details: {ping_out}")
        return None

    # Gather device info
    serial        = adb_run(adb, device_args, "get-serialno").stdout.strip()
    model         = adb_shell(adb, device_args, "getprop ro.product.model")
    brand         = adb_shell(adb, device_args, "getprop ro.product.brand")
    android_ver   = adb_shell(adb, device_args, "getprop ro.build.version.release")
    android_sdk   = adb_shell(adb, device_args, "getprop ro.build.version.sdk")
    build_type    = adb_shell(adb, device_args, "getprop ro.build.type")

    log_ok("Device reachable!")
    log_info(f"Serial  : {serial or 'unknown'}")
    log_info(f"Device  : {brand} {model}")
    log_info(f"Android : {android_ver}  (SDK {android_sdk})")
    log_info(f"Build   : {build_type}")

    return {
        "serial": serial,
        "model": model,
        "brand": brand,
        "android_ver": android_ver,
        "android_sdk": android_sdk,
        "build_type": build_type,
    }


# ── Root method detection ─────────────────────────────────────────────────────
def detect_root(adb: str, device_args: list[str]) -> tuple[str, str]:
    """
    Try each root method in order.
    Returns (root_method, root_label).
    """
    log_step("Root method detection")

    def probe(method_label: str, cmd: str) -> bool:
        out = adb_shell(adb, device_args, cmd)
        if "uid=0" in out:
            log_ok(f"Method works: {method_label}")
            return True
        log_info(f"Method failed: {method_label}  (got: {out or '<no output>'})")
        return False

    # Method 1 — adb root
    log_info("Trying: adb root  (restarts adbd — requires userdebug/eng build)")
    adbd_result = run([adb] + device_args + ["root"])
    adbd_out = (adbd_result.stdout + adbd_result.stderr).replace("\r", "")
    if not any(kw in adbd_out for kw in ("adbd cannot run as root", "error", "failed")):
        time.sleep(1)
        if probe("adb root → plain shell id", "id"):
            return "adb_root", "adb root  (adbd restarted as root — plain shell commands work directly)"

    # Method 2 — su -c '...'
    log_info("Trying: su -c 'cmd'  (Android ≥10, Magisk, most AVDs)")
    if probe("su -c 'id'", "su -c 'id'"):
        return "su_c", "su -c 'cmd'  (Android ≥10 / Magisk style)"

    # Method 3 — su 0 -c '...'
    log_info("Trying: su 0 -c 'cmd'  (LineageOS / some custom ROMs)")
    if probe("su 0 -c 'id'", "su 0 -c 'id'"):
        return "su_0_c", "su 0 -c 'cmd'  (LineageOS / custom ROM style)"

    # Method 4 — su 0 cmd
    log_info("Trying: su 0 cmd  (Android ≤9 / older ROMs)")
    if probe("su 0 id", "su 0 id"):
        return "su_0", "su 0 cmd  (Android ≤9 / older ROM style)"

    # Method 5 — shell already root
    log_info("Trying: plain shell — checking if already uid=0")
    if probe("plain shell id (already root?)", "id"):
        return "shell_root", "plain shell already runs as root (no su needed)"

    return "none", "No root access detected"


# ── Summary ───────────────────────────────────────────────────────────────────
def print_summary(root_method: str, root_label: str, device_args: list[str]) -> int:
    log_step("Result")

    flag_str = " ".join(device_args)

    if root_method == "none":
        log_warn("Root method : NONE")
        log_warn("No root access could be obtained on this device.")
        log_warn("Ensure the device has a rooted build (userdebug/eng AVD, Magisk, etc.)")
        print(f"\n{C_BOLD}ROOT_METHOD=none{C_RESET}")
        return 2

    log_ok(f"Root method : {root_method}")
    log_info(f"Description : {root_label}")
    log_info("")
    log_info("To use in your scripts, call root commands as follows:")
    print()

    examples = {
        "adb_root": (
            f"    {C_BOLD}adb {flag_str} shell 'your_command_here'{C_RESET}\n"
            f"    {C_INFO}(adbd already runs as root — no su wrapper needed){C_RESET}"
        ),
        "su_c": (
            f"    {C_BOLD}adb {flag_str} shell \"su -c 'your_command_here'\"{C_RESET}"
        ),
        "su_0_c": (
            f"    {C_BOLD}adb {flag_str} shell \"su 0 -c 'your_command_here'\"{C_RESET}"
        ),
        "su_0": (
            f"    {C_BOLD}adb {flag_str} shell 'su 0 your_command_here'{C_RESET}"
        ),
        "shell_root": (
            f"    {C_BOLD}adb {flag_str} shell 'your_command_here'{C_RESET}\n"
            f"    {C_INFO}(shell user is already uid=0){C_RESET}"
        ),
    }
    print(examples.get(root_method, ""))
    print()
    print(f"{C_BOLD}ROOT_METHOD={root_method}{C_RESET}")
    return 0


# ── Main ──────────────────────────────────────────────────────────────────────
def main() -> None:
    parser = argparse.ArgumentParser(
        description="Detect ADB connectivity and root method on an Android device.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  %(prog)s                  # auto-detect\n"
            "  %(prog)s -e               # emulator only\n"
            "  %(prog)s -d               # USB device only\n"
            "  %(prog)s -s emulator-5554 # specific serial\n\n"
            "Environment:\n"
            "  ADB=/path/to/adb   override adb binary"
        ),
    )
    group = parser.add_mutually_exclusive_group()
    group.add_argument("-e", dest="device", action="store_const", const="-e",
                       help="target emulator")
    group.add_argument("-d", dest="device", action="store_const", const="-d",
                       help="target USB device")
    group.add_argument("-s", dest="serial", metavar="SERIAL",
                       help="target specific device by serial")
    args = parser.parse_args()

    adb = resolve_adb()

    # Build device_args list and label
    if args.serial:
        device_args = ["-s", args.serial]
        auto_detect = False
        label = f"serial {args.serial}"
    elif args.device:
        device_args = [args.device]
        auto_detect = False
        label = "emulator" if args.device == "-e" else "USB device"
    else:
        auto_detect = True
        device_args = ["-e"]
        label = "auto-detect"

    # ── Auto-detect ───────────────────────────────────────────────────────────
    if auto_detect:
        log_info("No device flag given — auto-detecting...")
        device_args = ["-e"]
        info = check_connectivity(adb, device_args, "emulator")
        if info:
            log_ok("Using emulator.")
        else:
            log_warn("No emulator found. Trying USB device...")
            device_args = ["-d"]
            info = check_connectivity(adb, device_args, "USB device")
            if info:
                log_ok("Using USB device.")
            else:
                log_err("No reachable device found (emulator or USB).")
                log_err("Run 'adb devices' to inspect the current state.")
                sys.exit(1)
    else:
        info = check_connectivity(adb, device_args, label)
        if not info:
            sys.exit(1)

    # ── Root detection ────────────────────────────────────────────────────────
    root_method, root_label = detect_root(adb, device_args)

    exit_code = print_summary(root_method, root_label, device_args)
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
