# Native Chromium .deb for Ubuntu 26.04

Install **native Chromium as a real `.deb` package** on Ubuntu 26.04 (Resolute), without using the Ubuntu Chromium Snap.

This guide uses the **XtraDeb Apps PPA**:

```text
ppa:xtradeb/apps
```

XtraDeb is a third-party community repository. It is **not** maintained by Google, the Chromium project, or Canonical.

The XtraDeb repository provides Ubuntu 26.04 Chromium packages for both **AMD64** and **ARM64**.

## 1. Update Ubuntu

On a fresh Ubuntu 26.04 installation:

```bash
sudo apt update
sudo apt upgrade
sudo reboot
```

After reboot, continue below.

## 2. Remove Ubuntu Chromium / Snap if installed

Ubuntu normally distributes Chromium as a Snap. Remove it before installing the native XtraDeb version.

Remove the Snap if it exists:

```bash
sudo snap remove chromium
```

Remove Ubuntu Chromium transition packages if they exist:

```bash
sudo apt remove chromium chromium-browser -y
```

It is not necessary to install Ubuntu's Chromium first.

## 3. Add the XtraDeb repository

Install the repository management command if needed:

```bash
sudo apt install software-properties-common -y
```

Add XtraDeb:

```bash
sudo add-apt-repository ppa:xtradeb/apps
```

## 4. Pin XtraDeb to Chromium only

XtraDeb contains many applications. This pin gives XtraDeb priority for Chromium, while keeping the rest of Ubuntu on the normal Ubuntu repositories.

Create:

```bash
sudo nano /etc/apt/preferences.d/xtradeb-chromium
```

Add:

```text
Package: *
Pin: release o=LP-PPA-xtradeb-apps
Pin-Priority: 100

Package: chromium*
Pin: release o=LP-PPA-xtradeb-apps
Pin-Priority: 700
```

Save the file and update APT:

```bash
sudo apt update
```

You can verify which Chromium package APT will install:

```bash
apt-cache policy chromium
```

The candidate should come from the XtraDeb PPA.

## 5. Install native Chromium

Install Chromium:

```bash
sudo apt install chromium
```

Check the installed version:

```bash
chromium --version
```

Check the package:

```bash
dpkg -l chromium chromium-common chromium-sandbox
```

This is a native Debian/Ubuntu package installation, not Chromium Snap or Flatpak.

## 6. Add Google services / Sync support

Optional.

Download the Chromium Google services script:

```bash
wget -O chromium-google-sync.sh https://wobbo.org/2026-09-30/chromium-google-sync.sh
chmod +x chromium-google-sync.sh
./chromium-google-sync.sh
```

Project:

https://github.com/wobbo/chromium-google-sync

## 7. Add Widevine DRM

Optional, but required for services such as Netflix that use Widevine DRM.

Download the Widevine installer:

```bash
wget -O install-widevine.sh https://wobbo.org/2026-10-01/install-widevine.sh
chmod +x install-widevine.sh
./install-widevine.sh
```

The Widevine installer supports:

- AMD64 / x86-64
- ARM64 / AArch64

It downloads the matching official Google Chrome `.deb`, extracts only Google's Widevine CDM, and installs it into Chromium. Google Chrome itself is not installed.

Project:

https://github.com/wobbo/chromium-widevine

## Updating Chromium

Normal APT updates will update the native Chromium package:

```bash
sudo apt update
sudo apt upgrade
```

Because of the APT pin, Chromium can continue to update from XtraDeb without giving the entire XtraDeb repository priority over Ubuntu.

## If APT or dpkg is stuck

**Do not remove APT/dpkg lock files while package management is still running.**

First check:

```bash
ps -ef | grep -E 'apt|apt-get|dpkg'
```

If an update is genuinely still running, let it finish.

If `apt` or `apt-get` has actually hung and you have confirmed that it needs to be stopped:

```bash
sudo killall apt apt-get
```

Only after confirming that no APT/dpkg operation is still active, stale lock files can be removed:

```bash
sudo rm -f /var/lib/apt/lists/lock
sudo rm -f /var/cache/apt/archives/lock
sudo rm -f /var/lib/dpkg/lock
sudo rm -f /var/lib/dpkg/lock-frontend
```

Repair any interrupted package configuration:

```bash
sudo dpkg --configure -a
sudo apt --fix-broken install
sudo apt update
```

Then update the system normally:

```bash
sudo apt upgrade
```

Reboot if required:

```bash
sudo reboot
```

## Notes

- Tested target: Ubuntu 26.04 (Resolute).
- Native Chromium is installed from XtraDeb, not from Ubuntu's Chromium Snap.
- XtraDeb is a third-party PPA.
- The PPA is pinned so that only Chromium packages receive higher priority.
- AMD64 and ARM64 packages are available for Ubuntu 26.04.
- Google Sync/services and Widevine are optional additions and are maintained as separate projects.

## Author

Ernst Lanser  
<ernst.lanser@wobbo.org>

https://github.com/wobbo/
