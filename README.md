# Chromium DEB for Ubuntu 26.04

Install Chromium on Ubuntu 26.04 as a native `.deb` package instead of Snap.

## Chromium package: XtraDeb

The Chromium `.deb` packages used here are built and maintained by the **XtraDeb project** through:

```text
ppa:xtradeb/apps
```

XtraDeb is a third-party Ubuntu package project. It is not maintained by Google, the Chromium project or Canonical.

**This repository does not build or maintain Chromium itself.** It only explains and automates how to install the XtraDeb Chromium package on Ubuntu 26.04.

XtraDeb deserves the credit for providing the native Chromium `.deb` packages.

**Many thanks to the XtraDeb project and its maintainers for the hard work of building, packaging and maintaining Chromium as native Ubuntu `.deb` packages.** Without their work, this installation method would not exist.

## Automatic installation

```bash
wget -O install-chromium.sh https://raw.githubusercontent.com/wobbo/chromium-ubuntu/main/install-chromium.sh
chmod +x install-chromium.sh
./install-chromium.sh
```

No reboot is required.

## Manual installation

### 1. Repair APT/dpkg

I needed these commands first because APT was stuck on my Ubuntu 26.04 installation:

```bash
sudo killall apt apt-get
sudo rm /var/lib/apt/lists/lock
sudo rm /var/cache/apt/archives/lock
sudo rm /var/lib/dpkg/lock*
sudo dpkg --configure -a
```

### 2. Remove Ubuntu Chromium/Snap and update Ubuntu

```bash
sudo snap remove chromium
sudo apt remove chromium chromium-browser -y
sudo apt update && sudo apt upgrade
```

### 3. Add XtraDeb

```bash
sudo add-apt-repository ppa:xtradeb/apps
```

### 4. Give XtraDeb priority only for Chromium

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

This keeps normal Ubuntu packages on the Ubuntu repositories, while Chromium can come from XtraDeb.

### 5. Install Chromium

```bash
sudo apt update && sudo apt install chromium
```

Chromium is now installed as a native `.deb` package.

## Google services

Optional Google services for Chromium:

https://github.com/wobbo/chromium-google-sync

## Widevine DRM

Widevine is Google's DRM system for protected video playback.

It is needed by services such as **Netflix** and other streaming websites that use Widevine-protected video. Chromium can work normally without Widevine, but protected video may not play.

Widevine installer:

https://github.com/wobbo/chromium-widevine

## Author

Installation guide and script:

Ernst Lanser  
<ernst.lanser@wobbo.org>

https://github.com/wobbo/

Chromium `.deb` packages are provided by **XtraDeb**.
