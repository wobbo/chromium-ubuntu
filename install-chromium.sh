#!/bin/bash
# Native Chromium DEB Installer for Ubuntu 26.04
# 2026-10-03 v1.2
# Ernst Lanser <ernst.lanser@wobbo.org>
# https://github.com/wobbo/
#
# Chromium packages are built and maintained by XtraDeb, not by this project.
# Many thanks to the XtraDeb maintainers for their hard work!
# https://xtradeb.net/
# https://salsa.debian.org/xtradeb-team

set -Eeuo pipefail

VERSION=1.2
TRANSITION_PACKAGES=(chromium-browser chromium-browser-l10n chromium-chromedriver
    chromium-codecs-ffmpeg chromium-codecs-ffmpeg-extra)
INSTALL_PACKAGES=(chromium gnome-software gnome-software-plugin-deb packagekit)
WORK_DIR=
SNAP_AVAILABLE=0
SNAPD_REMOVED=0
RUNTIME_SNAPS=()

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '\n%s\n' "$*"; }
apt_run() { apt-get -o DPkg::Lock::Timeout=120 "$@"; }

package_present() {
    local state
    state=$(dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null) || return 1
    [[ $state == installed || $state == config-files ]]
}

is_chromium_snap() { [[ $1 =~ ^chromium(_[a-z0-9]+)?$ ]]; }

is_runtime_snap() {
    # Conservative list: an unknown snap is treated as an app and retained.
    [[ $1 =~ ^(snapd|bare|core([0-9]+)?|gtk-common-themes|chromium-ffmpeg|gnome-[0-9]+-[0-9]+|mesa-[0-9]+)$ ]]
}

assert_platform() {
    [[ $1 == ubuntu && $2 == 26.04 ]] ||
        die 'This installer supports Ubuntu 26.04 only.'
    [[ $3 == amd64 || $3 == arm64 ]] ||
        die "Unsupported architecture: $3 (expected amd64 or arm64)."
}

check_platform() {
    # shellcheck disable=SC1091
    . /etc/os-release
    assert_platform "${ID:-}" "${VERSION_ID:-}" "$(dpkg --print-architecture)"
}

ensure_root() {
    if (( EUID != 0 )); then
        command -v sudo >/dev/null 2>&1 || die 'sudo is required, or run this script as root.'
        exec sudo -- bash "$0" "$@"
    fi
}

confirm_install() {
    cat <<'NOTICE'

This installer will:
  * Close running Chromium sessions for ALL users (save your work first).
  * Replace Chromium Snap with the XtraDeb Chromium DEB for all users.
  * PERMANENTLY DELETE Chromium Snap profiles, bookmarks, passwords, history,
    cache, saved Snap snapshots and old Snap launchers for all local users.
    Export anything you want to keep BEFORE continuing. No backup is made.
  * Remove empty ~/snap folders. Other applications' user data is retained.
  * Remove snapd and unused Snap runtimes ONLY if no other Snap apps remain
    and there are no saved snapshots belonging to other apps.
  * Block Ubuntu's Chromium-to-Snap packages. If snapd is removed, block its
    automatic reinstallation through APT too.
  * Enable DEB updates through GNOME Software using the XtraDeb repository.

Existing DEB profiles in ~/.config/chromium are kept.
Other Snap apps (including Firefox or App Center) are kept if installed.
NOTICE
    local answer
    read -r -p 'Continue with installation and permanent Snap cleanup? [y/N] ' answer || return 1
    [[ $answer == [yY] || $answer == [yY][eE][sS] ]]
}

write_chromium_pin() {
    cat >"$WORK_DIR/xtradeb-chromium" <<'PINS'
# Managed by chromium-ubuntu: prefer XtraDeb and block Ubuntu Snap transitions.
Package: *
Pin: release o=LP-PPA-xtradeb-apps
Pin-Priority: 100

Package: chromium*
Pin: release o=LP-PPA-xtradeb-apps
Pin-Priority: 700

Package: chromium-browser chromium-browser-l10n chromium-chromedriver chromium-codecs-ffmpeg chromium-codecs-ffmpeg-extra
Pin: release o=Ubuntu
Pin-Priority: -1
PINS
    install -d -m 0755 /etc/apt/preferences.d
    install -m 0644 "$WORK_DIR/xtradeb-chromium" /etc/apt/preferences.d/xtradeb-chromium
}

check_candidate() {
    /usr/bin/python3 - <<'CANDIDATE_PY'
import apt
cache = apt.Cache()
candidate = cache["chromium"].candidate if "chromium" in cache else None
if not candidate or not any(o.origin == "LP-PPA-xtradeb-apps" for o in candidate.origins):
    raise SystemExit("ERROR: No XtraDeb Chromium candidate. Check APT sources/pins; Snap has not been removed.")
print(f"XtraDeb candidate: {candidate.version} ({candidate.architecture})")
CANDIDATE_PY
}

check_removals() {
    local plan=$1 package allowed found
    shift
    while read -r package; do
        package=${package%%:*}
        found=0
        for allowed in "$@"; do
            if [[ $package == "$allowed" ]]; then found=1; break; fi
        done
        [[ $found == 1 ]] || die "APT also wants to remove $package. Resolve this before continuing."
    done < <(awk '$1 == "Remv" || $1 == "Purg" {print $2}' "$plan")
}

read_snap_list() {
    # Do not mistake an unavailable snapd service for an empty installation.
    snap list >"$WORK_DIR/snap-list" 2>"$WORK_DIR/snap-error" || {
        cat "$WORK_DIR/snap-error" >&2
        die 'Cannot inspect Snap. Restore the snapd service and rerun the installer.'
    }
    awk 'NR > 1 && $1 ~ /^[a-z0-9][a-z0-9_-]*$/ {print $1}' "$WORK_DIR/snap-list" >"$WORK_DIR/snap-names"
}

inspect_snap() {
    local state
    state=$(dpkg-query -W -f='${db:Status-Status}' snapd 2>/dev/null) || state=absent
    if [[ $state == installed ]] && command -v snap >/dev/null 2>&1; then
        SNAP_AVAILABLE=1
        read_snap_list
        snap saved >"$WORK_DIR/snap-saved"
    elif [[ $state == installed ]]; then
        die 'snapd is installed but its snap command is missing. Repair snapd first.'
    fi
}

close_chromium() {
    /usr/bin/python3 - <<'CLOSE_PY'
import os
import re
import signal
import time
from pathlib import Path

def chromium_pids():
    found = []
    for proc in Path("/proc").glob("[0-9]*"):
        try:
            exe = os.readlink(proc / "exe")
        except OSError:
            continue
        # Snap's process is sometimes named chrome. Do not close Google Chrome.
        if re.match(r"^/(?:usr/lib/(?:chromium|chromium-browser)/|snap/chromium(?:_[a-z0-9]+)?/)", exe):
            found.append(int(proc.name))
    return found

def send(sig):
    for pid in chromium_pids():
        try:
            os.kill(pid, sig)
        except ProcessLookupError:
            pass

send(signal.SIGTERM)
deadline = time.monotonic() + 10
while chromium_pids() and time.monotonic() < deadline:
    time.sleep(0.2)
if chromium_pids():
    print("Closing remaining Chromium processes...")
    send(signal.SIGKILL)
    time.sleep(0.5)
if chromium_pids():
    raise SystemExit("ERROR: Chromium is still running. Close it in all sessions and retry.")
CLOSE_PY
}

remove_chromium_snaps() {
    [[ $SNAP_AVAILABLE == 1 ]] || return 0
    local name set_id
    while read -r name; do
        if is_chromium_snap "$name"; then snap remove --purge "$name"; fi
    done <"$WORK_DIR/snap-names"
    # Forget only Chromium entries, even when a snapshot set contains other apps.
    while read -r set_id name; do
        if is_chromium_snap "$name"; then snap forget "$set_id" "$name"; fi
    done < <(awk '$1 ~ /^[0-9]+$/ {print $1, $2}' "$WORK_DIR/snap-saved")
    read_snap_list
    while read -r name; do
        if is_chromium_snap "$name"; then die "Chromium Snap remains installed: $name"; fi
    done <"$WORK_DIR/snap-names"
}

remove_unused_snapd() {
    [[ $SNAP_AVAILABLE == 1 ]] || return 0
    local name
    local apps=() runtimes=() bases=()
    read_snap_list
    while read -r name; do
        if is_runtime_snap "$name"; then
            case $name in
                core|core[0-9]*|bare|snapd) bases+=("$name") ;;
                *) runtimes+=("$name") ;;
            esac
        else
            apps+=("$name")
        fi
    done <"$WORK_DIR/snap-names"
    if ((${#apps[@]})); then
        printf 'Keeping Snap for other apps: %s\n' "${apps[*]}"
        return 0
    fi
    snap saved >"$WORK_DIR/snap-saved-after"
    if awk '$1 ~ /^[0-9]+$/ {found=1} END {exit !found}' "$WORK_DIR/snap-saved-after"; then
        info 'Keeping snapd: saved data for other snaps still exists.'
        return 0
    fi
    local purge=(snapd)
    if package_present gnome-software-plugin-snap; then purge+=(gnome-software-plugin-snap); fi
    apt_run -s purge "${purge[@]}" >"$WORK_DIR/purge-plan"
    check_removals "$WORK_DIR/purge-plan" "${purge[@]}"
    RUNTIME_SNAPS=("${runtimes[@]}" "${bases[@]}")
    # Remove content providers before their bases. Let snapd enforce dependencies.
    for name in "${runtimes[@]}"; do snap remove --purge "$name"; done
    for name in "${bases[@]}"; do
        if [[ $name != snapd ]]; then snap remove --purge "$name"; fi
    done
    for name in "${bases[@]}"; do
        if [[ $name == snapd ]]; then snap remove --purge "$name"; fi
    done
    read_snap_list
    [[ ! -s $WORK_DIR/snap-names ]] || die 'Snap packages remain; snapd will not be purged.'
    apt_run purge -y "${purge[@]}"
    cat >"$WORK_DIR/chromium-ubuntu-no-snapd" <<'NOSNAP'
# Managed by chromium-ubuntu after removing an unused Snap installation.
# Delete this file if you deliberately want to install Snap again.
Package: snapd gnome-software-plugin-snap
Pin: version *
Pin-Priority: -1
NOSNAP
    install -m 0644 "$WORK_DIR/chromium-ubuntu-no-snapd" /etc/apt/preferences.d/chromium-ubuntu-no-snapd
    SNAPD_REMOVED=1
}

cleanup_system() {
    local path name mount
    # snapd normally removes these. Also handle leftovers from an earlier removal.
    [[ ! -L /var/snap ]] || die 'Inspect the symlink /var/snap before cleaning system Snap data.'
    for path in /var/snap/chromium /var/snap/chromium_*; do
        [[ -e $path || -L $path ]] || continue
        name=${path##*/}
        is_chromium_snap "$name" || continue
        while read -r mount; do
            [[ $mount != "$path" && $mount != "$path/"* ]] || die "Snap data is still mounted: $path"
        done < <(findmnt -rn -o TARGET)
        rm -rf --one-file-system -- "$path"
    done
    for path in /var/lib/snapd/desktop/applications/chromium*_chromium.desktop; do
        [[ -e $path || -L $path ]] || continue
        name=${path##*/}
        if is_chromium_snap "${name%_chromium.desktop}"; then rm -f -- "$path"; fi
    done
}

cleanup_user() {
    local account=$1 account_home=$2
    # Run in each account's own security context, not as root for other users.
    runuser -u "$account" -- /usr/bin/python3 - "$account_home" "${RUNTIME_SNAPS[@]}" <<'CLEANUP_PY'
import ast
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

SNAP_NAME = re.compile(r"chromium(?:_[a-z0-9]+)?\Z")
SNAP_ID = re.compile(r"chromium(?:_[a-z0-9]+)?_chromium\.desktop")

def clean_user(profile, runtimes):
    profile = profile.resolve()

    def safe(path):
        # No traversal through a symlinked directory, including .local or snap.
        current = path.parent
        while current != profile:
            if current == current.parent or current.is_symlink():
                return False
            current = current.parent
        return True

    def remove(path):
        if not safe(path):
            raise RuntimeError(f"Refusing cleanup through a symlink: {path}")
        if path.is_symlink() or path.is_file():
            path.unlink()
        elif path.is_dir():
            # Never cross a mounted directory when removing leftovers.
            for root, dirs, _ in os.walk(path, followlinks=False):
                if os.path.ismount(root) or any(os.path.ismount(Path(root) / d) for d in dirs):
                    raise RuntimeError(f"Mounted data remains at {path}; close Snap and retry.")
            shutil.rmtree(path)

    # Handle the standard location and snapd's optional migrated home location.
    for folder in (profile / "snap", profile / "Snap", profile / ".snap/data"):
        if folder.is_symlink() or not safe(folder):
            if folder.exists():
                raise RuntimeError(f"Inspect this nonstandard Snap folder manually: {folder}")
            continue
        if folder.is_dir():
            for child in folder.iterdir():
                if SNAP_NAME.fullmatch(child.name) or child.name in runtimes:
                    remove(child)
            if not any(folder.iterdir()):
                folder.rmdir()

    config = profile / ".config"
    data = profile / ".local/share"
    desktop_dirs = [data / "applications", config / "autostart", profile / "Desktop"]
    user_dirs = config / "user-dirs.dirs"
    if safe(user_dirs) and not user_dirs.is_symlink() and user_dirs.is_file():
        match = re.search(r'^XDG_DESKTOP_DIR="([^"\n]*)"', user_dirs.read_text(), re.M)
        if match:
            custom = Path(match[1].replace("${HOME}", str(profile)).replace("$HOME", str(profile)))
            if custom.is_relative_to(profile) and custom != profile:
                desktop_dirs.append(custom)
    removed_ids = set()
    for directory in set(desktop_dirs):
        if directory.is_symlink() or not safe(directory / "entry") or not directory.is_dir():
            continue
        for launcher in directory.glob("*.desktop"):
            if launcher.is_symlink():
                target = str(launcher.resolve())
                is_snap = bool(re.search(r"/(?:snap|var/lib/snapd)/.*chromium", target))
            else:
                text = launcher.read_text(errors="replace")
                is_snap = bool(re.search(r"(?m)^X-SnapInstanceName=chromium(?:_[a-z0-9]+)?\s*$", text)
                    or re.search(r"(?m)^Exec=.*(?:/snap/bin/chromium(?:_[a-z0-9]+)?(?:\s|$)|snap run chromium(?:_[a-z0-9]+)?(?:\s|$))", text))
            if SNAP_ID.fullmatch(launcher.name) or is_snap:
                removed_ids.add(launcher.name)
                remove(launcher)

    icons = data / "icons"
    if icons.is_dir() and not icons.is_symlink() and safe(icons / "entry"):
        for root, dirs, files in os.walk(icons, followlinks=False):
            dirs[:] = [d for d in dirs if not (Path(root) / d).is_symlink()]
            for filename in files:
                if re.fullmatch(r"chromium(?:_[a-z0-9]+)?_chromium\.(?:png|svg|xpm)", filename):
                    remove(Path(root) / filename)

    def replace_id(value):
        return "chromium.desktop" if SNAP_ID.fullmatch(value) or value in removed_ids else value

    # Preserve the existing default-browser choice; only replace old Snap IDs.
    for directory in (config, data / "applications"):
        if directory.is_symlink() or not safe(directory / "entry") or not directory.is_dir():
            continue
        for mime in directory.glob("*mimeapps.list"):
            if mime.is_symlink():
                continue
            original = mime.read_text()
            lines = []
            for line in original.splitlines(keepends=True):
                if "=" in line and not line.lstrip().startswith(("#", ";")):
                    key, values = line.split("=", 1)
                    newline = "\n" if values.endswith("\n") else ""
                    entries = values.rstrip("\n").split(";")
                    line = key + "=" + ";".join(replace_id(e) for e in entries) + newline
                lines.append(line)
            updated = "".join(lines)
            if updated != original:
                mime.write_text(updated)

    # Replace an existing GNOME dock favourite rather than leaving a dead icon.
    if shutil.which("gsettings"):
        prefix = []
        bus = Path(f"/run/user/{os.getuid()}/bus")
        env = os.environ.copy()
        if bus.exists():
            env["DBUS_SESSION_BUS_ADDRESS"] = f"unix:path={bus}"
        elif shutil.which("dbus-run-session"):
            prefix = ["dbus-run-session", "--"]
        else:
            print(f"NOTICE: Log in as {profile.name} and replace any old Snap dock icon manually.")
            return
        cmd = prefix + ["gsettings"]
        result = subprocess.run(cmd + ["get", "org.gnome.shell", "favorite-apps"], env=env,
                                text=True, capture_output=True)
        if result.returncode == 0:
            try:
                old = ast.literal_eval(result.stdout.strip().removeprefix("@as "))
                new = [replace_id(x) for x in old]
                if new != old:
                    new = list(dict.fromkeys(new))
                    subprocess.run(cmd + ["set", "org.gnome.shell", "favorite-apps", repr(new)],
                                   env=env, check=True)
            except (ValueError, SyntaxError, subprocess.CalledProcessError) as error:
                print(f"NOTICE: Could not update the GNOME dock for {profile.name}: {error}")

if __name__ == "__main__":
    clean_user(Path(sys.argv[1]), sys.argv[2:])
CLEANUP_PY
}

cleanup_users() {
    local account password uid gid gecos account_home shell
    while IFS=: read -r account password uid gid gecos account_home shell; do
        if (( uid == 0 || (uid >= 1000 && uid < 65534) )); then
            [[ $account_home == /* && $account_home != / && -d $account_home ]] || continue
            printf 'Cleaning old Chromium Snap files for %s...\n' "$account"
            cleanup_user "$account" "$account_home"
        fi
    done </etc/passwd
}

main() {
    export LC_ALL=C
    case ${1:-} in
        --version) printf '%s\n' "$VERSION"; return ;;
        --help) printf 'Usage: %s [--help|--version]\nInteractive Chromium DEB installer for Ubuntu 26.04.\n' "$0"; return ;;
        '') ;;
        *) die "Unknown argument: $1" ;;
    esac
    check_platform
    ensure_root "$@"
    printf 'Native Chromium DEB Installer for Ubuntu 26.04 v%s\n' "$VERSION"
    if ! confirm_install; then info 'Cancelled. No changes made.'; return 0; fi
    WORK_DIR=$(mktemp -d /tmp/chromium-ubuntu.XXXXXXXX)
    trap 'rm -rf -- "$WORK_DIR"' EXIT
    trap 'printf "\nInstallation stopped at line %s. Fix the reported error, then rerun this script.\n" "$LINENO" >&2' ERR

    local audit pkg
    audit=$(dpkg --audit)
    [[ -z $audit ]] || die "dpkg needs attention first: $audit"
    inspect_snap
    info 'Configuring APT and checking the XtraDeb package...'
    write_chromium_pin
    apt_run -o APT::Update::Error-Mode=any update
    apt_run install -y --no-install-recommends software-properties-common python3-apt
    add-apt-repository -y --no-update ppa:xtradeb/apps
    apt_run -o APT::Update::Error-Mode=any update
    check_candidate

    local remove_args=()
    for pkg in "${TRANSITION_PACKAGES[@]}"; do
        if package_present "$pkg"; then remove_args+=("$pkg-"); fi
    done
    apt_run -s --no-install-recommends --purge install "${INSTALL_PACKAGES[@]}" "${remove_args[@]}" >"$WORK_DIR/install-plan"
    check_removals "$WORK_DIR/install-plan" "${TRANSITION_PACKAGES[@]}"
    # Fetch all DEBs before deleting the old browser or its data.
    apt_run --download-only --no-install-recommends --purge install -y "${INSTALL_PACKAGES[@]}" "${remove_args[@]}"

    info 'Closing Chromium and removing its Snap installation and snapshots...'
    close_chromium
    remove_chromium_snaps
    info 'Installing Chromium DEB and GNOME Software DEB support...'
    apt_run --no-install-recommends --purge install -y "${INSTALL_PACKAGES[@]}" "${remove_args[@]}"
    [[ $(dpkg-query -W -f='${db:Status-Status}' chromium) == installed ]] || die 'Chromium DEB was not installed.'
    [[ -x /usr/bin/chromium && -f /usr/share/applications/chromium.desktop ]] || die 'The Chromium DEB executable or desktop launcher is missing.'
    remove_unused_snapd
    cleanup_system
    cleanup_users
    info 'Chromium DEB installed successfully for all users:'
    /usr/bin/chromium --version
    printf '\nUpdates: open GNOME Software > Updates > Refresh. XtraDeb supplies new versions.\n'
    printf 'You do not need to run this installer again for Chromium updates.\n'
    printf 'Reopen GNOME Software and your terminal to refresh any cached launchers.\n'
    if [[ $SNAPD_REMOVED == 1 ]]; then
        printf 'Unused Snap infrastructure was removed and its APT reinstallation is blocked.\n'
    fi
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
