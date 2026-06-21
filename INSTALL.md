# Installation Guide

## Option 1: Pre-built Image (Quickest)
1. Download `RandnetPi-v0.1.img.zip` from the [Releases page](https://github.com/2cans1string/RandnetPi/releases)
2. Extract the zip to get `RandnetPi-v0.1.img`
3. Flash to an 8GB or larger SD card using [Raspberry Pi Imager](https://www.raspberrypi.com/software/) (choose "Use custom") or Balena Etcher
4. Insert card into your Pi, connect ethernet, power on
5. Wait for first boot to complete — see First Boot Timing below
6. Connect your 64DD and dial in

## Option 2: Install from Source (Advanced)
1. Flash a stock [DreamPi 2.0.1](https://dreamcastlive.net) image to your SD card
2. Boot the Pi, connect ethernet, SSH in:
   ssh pi@<your-pi-ip>
   Default password: raspberry
3. Clone the repo and run the installer:
   git clone https://github.com/2cans1string/RandnetPi.git
   cd RandnetPi
   sudo bash install_randnet.sh 2>&1 | tee ~/install_log.txt
4. The installer takes 15-30 minutes depending on Pi model
5. Connect your 64DD and dial in

## First Boot Timing

After flashing the pre-built image and powering on, allow time before attempting SSH:

| Pi Model  | Wait Time   |
|-----------|-------------|
| Pi 2B     | 5 minutes   |
| Pi 3/3B+  | 3-4 minutes |
| Pi 4      | 2 minutes   |

What happens during first boot:
- 0-60s — Linux boots, systemd starts services
- 60-90s — dhcpcd obtains IP from your DHCP server
- 90-150s — randnet-firstboot detects eth0 IP, rewrites dnsmasq and iptables, restarts services, disables itself permanently
- 150-180s — Tomcat fully initialises

Tip: Use ping <pi-ip> to check when the Pi is reachable, then wait a further 30 seconds before SSH. The Pi appears on your network with hostname dreampi — check your router DHCP lease table if you do not know its IP.

## Monitoring

ssh pi@<your-pi-ip>
sudo journalctl -u dreampi -f
sudo journalctl -u tomcat -f
sudo tail -f /var/log/squid/access.log
