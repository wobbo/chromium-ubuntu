# Chromium DEB for Ubuntu 26.04

Install Chromium as a native `.deb` package from **XtraDeb**.

**Version 1.3 — 2026-10-03** · Ubuntu 26.04 · AMD64 and ARM64

One system-wide installation serves all users. Each user has their own browser profile.

## Install

```bash
wget -O install-chromium.sh https://github.com/wobbo/chromium-ubuntu/releases/download/v1.3/install-chromium.sh
chmod +x install-chromium.sh
./install-chromium.sh
```

The script asks for your sudo password when needed. Starting it with `sudo` also works.
It displays an English explanation and a **yes/no question before making changes**.

**Read this before answering yes:**

- Running Chromium sessions are closed for **all users**. Save your work first.
- Chromium Snap is removed, including parallel Chromium Snap instances.
- **Old Snap browser profiles are permanently deleted for all local users:** bookmarks, passwords, history, cache and saved Chromium Snap snapshots. Export anything you want to keep first. Profiles are not migrated and no backup is made.
- Old Chromium Snap menu entries, desktop shortcuts and autostart entries are removed. Existing GNOME dock favourites and browser associations pointing to Chromium Snap are changed to the DEB launcher.
- Empty `~/snap` folders are removed. Other apps' data is kept. Existing DEB profiles in `~/.config/chromium` are kept.
- `snapd` and recognised, unused Snap runtimes are removed only when **no other Snap apps remain** and there are no saved snapshots for other snaps. Firefox, App Center/Snap Store and unknown snaps count as other apps, so they keep Snap installed.
- Ubuntu's Chromium-to-Snap transition packages are blocked. When the unused Snap system is removed, APT is also prevented from automatically reinstalling `snapd` and its GNOME Software plugin.

The installer checks Ubuntu and the architecture, verifies an XtraDeb candidate,
simulates the package changes and downloads the required DEBs **before removing Chromium Snap**.
It stops on errors. A working DEB installation can be updated by rerunning the script;
it is not uninstalled first.

The installer uses ordinary local accounts from `/etc/passwd`, including root, for
leftover user-file cleanup. Nonstandard or symlinked Snap data directories may need
manual attention. Reopen GNOME Software and your terminal after installation so
cached entries can refresh. No reboot is normally needed for Chromium itself.

## Updates through Ubuntu and GNOME Software

The XtraDeb PPA stays enabled. When XtraDeb publishes a newer compatible version,
Chromium is offered with the normal Ubuntu DEB updates, system-wide.

The installer installs **GNOME Software**, **`gnome-software-plugin-deb`** and
**PackageKit**. Open **Software → Updates → Refresh**. Chromium can be grouped
with other system/package updates. Ubuntu's Snap-based App Center is a different app.

You do **not** need to rerun this installer for updates. Terminal updates also work:

```bash
sudo apt update
sudo apt upgrade
```

This does not configure unattended installation of PPA updates. Update availability
depends on XtraDeb publishing a build for your Ubuntu release and architecture.

## How Snap blocking works

`/etc/apt/preferences.d/xtradeb-chromium` prefers XtraDeb for Chromium and blocks
Ubuntu's Chromium Snap transition packages:

```text
Package: *
Pin: release o=LP-PPA-xtradeb-apps
Pin-Priority: 100

Package: chromium*
Pin: release o=LP-PPA-xtradeb-apps
Pin-Priority: 700

Package: chromium-browser chromium-browser-l10n chromium-chromedriver chromium-codecs-ffmpeg chromium-codecs-ffmpeg-extra
Pin: release o=Ubuntu
Pin-Priority: -1
```

If other Snap apps remain, their Snap system continues working. This APT rule does
not prevent someone from deliberately using `snap install chromium`.

If `snapd` was removed, the additional file
`/etc/apt/preferences.d/chromium-ubuntu-no-snapd` blocks its APT reinstallation.
Remove that file only if you deliberately want Snap back.

## Quick checks

```bash
dpkg --print-architecture
dpkg-query -W -f='${Package} ${Version} ${Architecture}\n' chromium
apt-cache policy chromium chromium-browser
chromium --version
```

The Chromium candidate should come from XtraDeb (priority **700**). Available
Ubuntu Chromium transition versions should have priority **-1**.

The following commands only simulate package changes:

```bash
apt-get -s install chromium-browser
apt-get -s upgrade
```

The first must not offer the Ubuntu Chromium-to-Snap transition package. The second
must not bring that package back. If Snap was retained, `snap list` must not list Chromium.

To check multiple users, sign into a second user's desktop and open Chromium from
the app menu. It should open their own DEB profile. Start browsers without `sudo`.

If another package manager is running, wait for it to finish. **Do not delete APT
or dpkg lock files.** This installer never kills package managers or deletes locks,
and it does not perform a full Ubuntu upgrade.

## Chromium package: XtraDeb

The Chromium `.deb` packages are built and maintained by the **XtraDeb project**:

```text
ppa:xtradeb/apps
```

XtraDeb is a third-party Ubuntu package project. It is not maintained by Google,
the Chromium project or Canonical. **This repository does not build or maintain
Chromium itself.** It automates installation and the cleanup of Chromium Snap.

**Many thanks to the [XtraDeb project](https://salsa.debian.org/xtradeb-team) and its
maintainers for the hard work of building, packaging and maintaining Chromium as
native Ubuntu `.deb` packages.** Without their work, this installation method would
not exist. See also [xtradeb.net](https://xtradeb.net/).

## Optional Google services and Widevine

Google services: <https://github.com/wobbo/chromium-google-sync>

Widevine is Google's DRM system for protected video playback, used by Netflix and
other streaming services. Ordinary browsing works without Widevine, but protected
video may not play. Widevine is installed separately:
<https://github.com/wobbo/chromium-widevine>

## Validation

Development checks, which do not install or remove system packages:

```bash
bash -n install-chromium.sh
python3 -m unittest discover -s tests -v
```

Tests cover deletion boundaries, preserved DEB/other-app profiles, snapshot scope,
Snap retention, confirmation, and failure paths using temporary files and mocked
package commands. They do not replace testing on real Ubuntu 26.04 AMD64 and ARM64
desktops, including a second user and a subsequent XtraDeb update.

## Version history

### v1.2 — 2026-10-03

- Adds explicit confirmation, platform checks and pre-download of replacement DEBs.
- Closes Chromium and removes Chromium Snap data, snapshots and old launchers.
- Removes and blocks unused Snap infrastructure when other apps/data do not need it.
- Enables GNOME Software DEB updates, including its separate DEB plugin.
- Keeps existing DEB profiles and installations when rerun.
- Replaces forced APT repair, ignored errors and full upgrades with checked operations.

### v1.1 — 2026-10-02

- Blocks Ubuntu Chromium transition packages that can reinstall Chromium Snap.
- Keeps XtraDeb preferred for Chromium.
- Clarifies system-wide installation, AMD64 and ARM64 support.

### v1.0 — 2026-10-01

- Initial XtraDeb Chromium DEB installer for Ubuntu 26.04.

## Author

Installation guide and script: **Ernst Lanser**  
<ernst.lanser@wobbo.org>  
<https://github.com/wobbo/>

Chromium `.deb` packages are provided by **XtraDeb**.
