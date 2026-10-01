# Chromium DEB for Ubuntu 26.04

Install Chromium on Ubuntu 26.04 as a native `.deb` package instead of Snap.

This uses the third-party XtraDeb PPA:

```text
ppa:xtradeb/apps
```

XtraDeb is not maintained by Google, Chromium or Canonical.

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

## Google services and Widevine

Google services:

https://github.com/wobbo/chromium-google-sync

Widevine DRM:

https://github.com/wobbo/chromium-widevine

## Author

Ernst Lanser  
<ernst.lanser@wobbo.org>

https://github.com/wobbo/
