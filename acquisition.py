#!/usr/bin/env python3
"""
acquisition.py
Acquires app data from an Android device/emulator via ADB.

Usage:
    python acquisition.py app.full.name [-d|-e]

Examples:
    python acquisition.py com.google.android.inputmethod.latin
    python acquisition.py com.google.android.inputmethod.latin -d

Environment:
    ADB=/path/to/adb   override adb binary (default: auto-detected from PATH)
"""

import argparse
import os
import shutil
import subprocess
import sys
import time
from datetime import datetime


# ── Colours ───────────────────────────────────────────────────────────────────
def _supports_colour() -> bool:
    """Return True if stdout is a terminal that likely supports ANSI codes."""
    if sys.platform == "win32":
        # Windows 10 1511+ supports ANSI in cmd/PowerShell when VT processing is on.
        try:
            import ctypes
            kernel32 = ctypes.windll.kernel32          # type: ignore[attr-defined]
            # Enable ENABLE_VIRTUAL_TERMINAL_PROCESSING (0x0004)
            kernel32.SetConsoleMode(kernel32.GetStdHandle(-11), 7)
            return True
        except Exception:
            return False
    return hasattr(sys.stdout, "isatty") and sys.stdout.isatty()


USE_COLOUR = _supports_colour()

C_RESET = "\033[0m"   if USE_COLOUR else ""
C_INFO  = "\033[0;36m" if USE_COLOUR else ""  # cyan
C_OK    = "\033[0;32m" if USE_COLOUR else ""  # green
C_WARN  = "\033[0;33m" if USE_COLOUR else ""  # yellow
C_ERR   = "\033[0;31m" if USE_COLOUR else ""  # red
C_BOLD  = "\033[1m"    if USE_COLOUR else ""
C_DIM   = "\033[2m"    if USE_COLOUR else ""


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

def log_sep() -> None:
    print(f"{C_DIM}────────────────────────────────────────{C_RESET}")

def die(msg: str) -> None:
    log_err(msg)
    sys.exit(1)


# ── ADB helpers ───────────────────────────────────────────────────────────────
def run(cmd: list[str], check: bool = False) -> subprocess.CompletedProcess:
    """Run a command, return CompletedProcess (stdout/stderr captured as text)."""
    return subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def adb_shell(adb: str, device_flag: str, cmd: str) -> str:
    """Run an adb shell command and return stdout stripped of CR/LF noise."""
    result = run([adb, device_flag, "shell", cmd])
    return result.stdout.replace("\r", "").strip()


def adb_root_shell(adb: str, device_flag: str, root_method: str, cmd: str) -> str:
    """Run a shell command with the detected root method."""
    dispatch = {
        "adb_root":   cmd,
        "shell_root": cmd,
        "su_c":       f"su -c '{cmd}'",
        "su_0_c":     f"su 0 -c '{cmd}'",
        "su_0":       f"su 0 {cmd}",
        "NONE":       cmd,
    }
    return adb_shell(adb, device_flag, dispatch[root_method])


# ── ADB binary validation ─────────────────────────────────────────────────────
def resolve_adb() -> str:
    log_step("ADB binary check")

    adb_env = os.environ.get("ADB", "")
    if adb_env:
        if not os.path.isfile(adb_env):
            die(f"ADB override '{adb_env}' does not exist.")
        if not os.access(adb_env, os.X_OK):
            die(f"ADB override '{adb_env}' is not executable.")
        log_info(f"Using override: {adb_env}")
        return adb_env

    adb = shutil.which("adb")
    if not adb:
        die("'adb' not found in PATH. Install Android SDK platform-tools or set ADB=/path/to/adb.")
    log_info(f"Found in PATH: {adb}")
    return adb


def validate_adb_version(adb: str) -> None:
    result = run([adb, "version"])
    if not result.stdout.strip():
        die(f"'{adb}' did not produce version output — the binary may be corrupt.")

    first_line = result.stdout.splitlines()[0]
    log_ok(first_line)

    # Parse version number (e.g. "1.0.41")
    import re
    m = re.search(r"(\d+)\.(\d+)\.(\d+)", result.stdout)
    if m:
        major, minor, patch = int(m.group(1)), int(m.group(2)), int(m.group(3))
        log_info(f"Version parsed: major={major} minor={minor} patch={patch}")
        if (major, minor, patch) < (1, 0, 39):
            log_warn(f"ADB version {major}.{minor}.{patch} is older than 1.0.39 — some features may not work.")


# ── Connectivity check ────────────────────────────────────────────────────────
def check_connectivity(adb: str, device_flag: str) -> None:
    log_step("Connectivity check")

    result = run([adb, "devices"])
    lines = [l for l in result.stdout.splitlines()[1:] if l.strip()]
    if not lines:
        die("No ADB devices found. Is the device on with USB debugging enabled?")

    log_info("ADB device list:")
    for line in lines:
        print(f"         {line}")

    if any("unauthorized" in line for line in lines):
        log_warn("At least one device shows 'unauthorized'.")
        log_warn("Accept the RSA fingerprint prompt on the device screen, then retry.")

    ping = adb_shell(adb, device_flag, "echo ping")
    if ping != "ping":
        die(f"Device ({device_flag}) did not respond. Details: {ping}")
    log_ok("Device is reachable.")


# ── Root method detection ─────────────────────────────────────────────────────
def detect_root(adb: str, device_flag: str) -> str:
    log_step("Root method detection")

    def probe(label: str, cmd: str) -> bool:
        out = adb_shell(adb, device_flag, cmd)
        if "uid=0" in out:
            log_ok(f"Works: {label}")
            return True
        log_info(f"Failed: {label}  (got: {out or '<no output>'})")
        return False

    # Method 1 — adb root
    log_info("Trying: adb root")
    r = run([adb, device_flag, "root"])
    adbd_out = (r.stdout + r.stderr).replace("\r", "")
    if not any(kw in adbd_out for kw in ("adbd cannot run as root", "error", "failed")):
        time.sleep(1)
        if probe("adb root → id", "id"):
            return "adb_root"

    # Method 2 — su -c '...'
    log_info("Trying: su -c 'cmd'")
    if probe("su -c 'id'", "su -c 'id'"):
        return "su_c"

    # Method 3 — su 0 -c '...'
    log_info("Trying: su 0 -c 'cmd'")
    if probe("su 0 -c 'id'", "su 0 -c 'id'"):
        return "su_0_c"

    # Method 4 — su 0 cmd
    log_info("Trying: su 0 cmd")
    if probe("su 0 id", "su 0 id"):
        return "su_0"

    # Method 5 — shell already root
    log_info("Trying: plain shell (already root?)")
    if probe("id (no su)", "id"):
        return "shell_root"

    log_warn("No root access detected. Acquisition may be incomplete.")
    log_warn("Ensure the device has a rooted build (userdebug AVD, Magisk, etc.)")
    return "NONE"


# ── Package lookup ────────────────────────────────────────────────────────────
def find_package(adb: str, device_flag: str, search_term: str) -> str:
    log_step("Package lookup")
    log_info(f'Searching for: "{search_term}"')

    output = adb_shell(adb, device_flag, "pm list packages")
    matches = [
        line.split(":", 1)[1].strip()
        for line in output.splitlines()
        if search_term in line and ":" in line
    ]

    if not matches:
        die(f'No packages found matching "{search_term}".')

    if len(matches) >= 2:
        log_warn(f"{len(matches)} matches found — please narrow down the search term:")
        for pkg in matches:
            print(f"         {pkg}")
        die("Ambiguous match. Exiting.")

    app = matches[0]
    log_ok(f"Package: {app}")
    return app


# ── Find app data folders ─────────────────────────────────────────────────────
def find_app_folders(adb: str, device_flag: str, root_method: str, app: str) -> list[str]:
    search_folders = [
        "/data_mirror/data_ce/",
        "/data/media/",
        "/data/user_de/",
        "/data/user/",
        "/storage/emulated/",
    ]

    seen_inodes: dict[str, bool] = {}
    found: list[str] = []

    for folder in search_folders:
        out = adb_root_shell(adb, device_flag, root_method,
                             f"find {folder} -type d -name {app} 2>/dev/null")
        for line in out.splitlines():
            line = line.strip()
            if line:
                found.append(line)

    if not found:
        die(f'No data folders found for "{app}". Is the app installed and has it been run?')

    log_sep()
    unique: list[str] = []
    for folder in found:
        inode = adb_root_shell(adb, device_flag, root_method,
                               f"stat -c %i '{folder}'").strip()
        if inode and inode not in seen_inodes:
            log_info(f"Adding : {folder}")
            seen_inodes[inode] = True
            unique.append(folder)
        else:
            log_info(f"Skipped (duplicate inode {inode}): {folder}")
    log_sep()
    return unique


# ── Main ──────────────────────────────────────────────────────────────────────
def main() -> None:
    parser = argparse.ArgumentParser(
        description="Acquire app data from an Android device/emulator via ADB.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  %(prog)s com.google.android.inputmethod.latin        # emulator (default)\n"
            "  %(prog)s com.google.android.inputmethod.latin -d     # USB device\n\n"
            "Environment:\n"
            "  ADB=/path/to/adb   override adb binary"
        ),
    )
    parser.add_argument("package", help="App package name (or search term)")
    parser.add_argument(
        "device",
        nargs="?",
        default="-e",
        choices=["-e", "-d"],
        help="-e emulator (default), -d USB device",
    )
    args = parser.parse_args()

    search_term: str = args.package
    device_flag: str = args.device
    devname = "emu" if device_flag == "-e" else "usb"

    # ── ADB ───────────────────────────────────────────────────────────────────
    adb = resolve_adb()
    validate_adb_version(adb)

    # ── Target device ─────────────────────────────────────────────────────────
    log_step("Target device")
    log_info(f"Target : {'emulator' if device_flag == '-e' else 'USB device'}")

    # ── Connectivity ──────────────────────────────────────────────────────────
    check_connectivity(adb, device_flag)

    # ── Root ──────────────────────────────────────────────────────────────────
    root_method = detect_root(adb, device_flag)
    if root_method != "NONE":
        log_ok(f"Root method: {root_method}")

    # ── Device info ───────────────────────────────────────────────────────────
    log_step("Device info")
    android_version = adb_shell(adb, device_flag, "getprop ro.build.version.release")
    android = android_version.split(".")[0] if android_version else "0"
    model = adb_shell(adb, device_flag, "getprop ro.product.model")
    brand = adb_shell(adb, device_flag, "getprop ro.product.brand")
    log_info(f"Device  : {brand} {model}")
    log_info(f"Android : {android_version}")

    # ── Package lookup ────────────────────────────────────────────────────────
    app = find_package(adb, device_flag, search_term)

    # ── Acquisition ───────────────────────────────────────────────────────────
    log_step("Acquisition")
    version_out = adb_shell(adb, device_flag, f"dumpsys package {app}")
    version = ""
    for line in version_out.splitlines():
        if "versionName" in line and "=" in line:
            version = line.split("=", 1)[1].strip()
            break

    timestamp = datetime.now().strftime("%Y.%m.%dT%H.%M.%S")
    filename = f"{app}-v{version}--{devname}{android}--{timestamp}"
    log_info(f"Version  : {version}")
    log_info(f"Filename : {filename}")

    # ── Find folders ──────────────────────────────────────────────────────────
    log_info("Searching for app data folders...")
    folders = find_app_folders(adb, device_flag, root_method, app)

    # Build the null-delimited file list on device
    for folder in folders:
        adb_root_shell(
            adb, device_flag, root_method,
            f"find '{folder}' -print0 >> /sdcard/Download/{filename}.txt"
        )

    # ── SHA256 checksums ──────────────────────────────────────────────────────
    log_info("Generating SHA256 checksums...")
    adb_root_shell(
        adb, device_flag, root_method,
        (
            f"cat /sdcard/Download/{filename}.txt "
            r"| xargs -0 sh -c 'for f; do [ -f \"$f\" ] && printf \"%s\0\" \"$f\"; done' _ "
            f"| xargs -0 sha256sum 2>/dev/null "
            f"| sed 's|  /|  |' "
            f"> /sdcard/Download/{filename}.sha256"
        ),
    )

    sha256_count = adb_root_shell(
        adb, device_flag, root_method,
        f"wc -l < /sdcard/Download/{filename}.sha256"
    ).strip()
    log_ok(f"Checksums computed: {sha256_count} file(s)")

    # ── Compress ──────────────────────────────────────────────────────────────
    log_info("Compressing...")
    adb_root_shell(
        adb, device_flag, root_method,
        (
            f"cat /sdcard/Download/{filename}.txt "
            f"| xargs -0 tar -czf /sdcard/Download/{filename}.tgz "
            f"-C /sdcard/Download {filename}.sha256"
        ),
    )
    log_ok(f"Compression done — {filename}.sha256 included in archive.")

    # ── Pull to local ─────────────────────────────────────────────────────────
    log_info("Copying to local storage...")
    pull = run([adb, device_flag, "pull", f"/sdcard/Download/{filename}.tgz", "."])
    if pull.returncode != 0:
        die(f"Pull failed. Check available disk space.\n{pull.stderr}")
    log_ok(f"Saved: ./{filename}.tgz")

    # ── Cleanup ───────────────────────────────────────────────────────────────
    log_info("Cleaning up device...")
    for remote in [
        f"/sdcard/Download/{filename}.tgz",
        f"/sdcard/Download/{filename}.txt",
        f"/sdcard/Download/{filename}.sha256",
    ]:
        run([adb, device_flag, "shell", f"rm {remote}"])
    log_ok("Device cleanup done.")

    log_sep()
    log_ok(f"Acquisition complete: {C_BOLD}./{filename}.tgz{C_RESET}")
    log_info("To verify integrity after extraction:")
    print(f"         {C_BOLD}tar -xzf {filename}.tgz{C_RESET}")
    print(f"         {C_BOLD}sha256sum -c {filename}.sha256{C_RESET}")
    log_sep()


if __name__ == "__main__":
    main()
