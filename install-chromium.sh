#!/bin/bash
#
# Native Chromium DEB Installer for Ubuntu 26.04
#
# Installs Chromium as a native .deb package from XtraDeb instead of Snap.
#
# 2026-10-02 v1.1
# Ernst Lanser <ernst.lanser@wobbo.org>
# https://github.com/wobbo/
#
# Many thanks to the XtraDeb project and its maintainers for the hard work of
# building, packaging and maintaining Chromium as native Ubuntu .deb packages.
# Without their work, this installation method would not exist.
# https://xtradeb.net/
# https://salsa.debian.org/xtradeb-team
#

set -e

echo "Native Chromium DEB Installer for Ubuntu 26.04 v1.1"
echo

echo "Repairing APT/dpkg..."
sudo killall apt apt-get 2>/dev/null || true
sudo rm -f /var/lib/apt/lists/lock
sudo rm -f /var/cache/apt/archives/lock
sudo rm -f /var/lib/dpkg/lock*
sudo dpkg --configure -a

echo
echo "Removing Ubuntu Chromium/Snap..."
if command -v snap >/dev/null 2>&1; then
    sudo snap remove chromium 2>/dev/null || true
fi
sudo apt remove chromium chromium-browser -y || true

echo
echo "Updating Ubuntu..."
sudo apt update
sudo apt upgrade -y

if ! command -v add-apt-repository >/dev/null 2>&1; then
    sudo apt install software-properties-common -y
fi

echo
echo "Adding XtraDeb..."
sudo add-apt-repository -y ppa:xtradeb/apps

echo
echo "Configuring APT priority and blocking Ubuntu Chromium Snap transition packages..."
sudo tee /etc/apt/preferences.d/xtradeb-chromium >/dev/null <<'EOF'
Package: *
Pin: release o=LP-PPA-xtradeb-apps
Pin-Priority: 100

Package: chromium*
Pin: release o=LP-PPA-xtradeb-apps
Pin-Priority: 700

Package: chromium-browser chromium-browser-l10n chromium-chromedriver chromium-codecs-ffmpeg chromium-codecs-ffmpeg-extra
Pin: release o=Ubuntu
Pin-Priority: -1
EOF

echo
echo "Installing Chromium..."
sudo apt update
sudo apt install chromium -y

echo
echo "Chromium installed successfully:"
chromium --version
