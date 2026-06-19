#!/bin/bash
# install_randnet.sh — Install Randnet 64DD revival config on DreamPi
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Randnet 64DD Revival — DreamPi Install Script ==="

# Enable IP forwarding
echo "Enabling IP forwarding..."
echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward > /dev/null
if grep -q "^#*net.ipv4.ip_forward" /etc/sysctl.conf; then
    sudo sed -i 's/^#*net.ipv4.ip_forward.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf
else
    echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf > /dev/null
fi

# Build and install the CHAP bypass plugin
echo "Building randnet_chap.so..."
cd "$SCRIPT_DIR/pppd_plugin"
make randnet_chap.so
sudo install -m 755 randnet_chap.so /etc/ppp/
echo "randnet_chap.so installed to /etc/ppp/"
cd "$SCRIPT_DIR"

# Install dnsmasq Randnet config and enable conf-dir
echo "Installing dnsmasq Randnet config..."
sudo mkdir -p /etc/dnsmasq.d
sudo cp "$SCRIPT_DIR/etc/dnsmasq.d/randnet.conf" /etc/dnsmasq.d/
if grep -q "^#conf-dir=/etc/dnsmasq.d" /etc/dnsmasq.conf; then
    sudo sed -i 's|^#conf-dir=/etc/dnsmasq.d|conf-dir=/etc/dnsmasq.d|' /etc/dnsmasq.conf
fi
sudo systemctl restart dnsmasq
echo "dnsmasq restarted with Randnet config"

echo ""
echo "=== Install complete ==="
echo "Edit RANDNET_SERVER_IP in dreampi.py to your revival server IP, then start dreampi."
