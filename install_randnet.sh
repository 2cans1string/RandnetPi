#!/bin/bash
# install_randnet.sh — Full Randnet 64DD revival setup
#
# Installs everything needed to run the full Randnet revival stack on a single
# Raspberry Pi (DreamPi + Randnet server in one device) or Ubuntu server.
#
# Edit the variables below before running.
#
# Usage:  chmod +x install_randnet.sh && sudo ./install_randnet.sh

set -e

# ─── Configuration ────────────────────────────────────────────────────────────

RANDNET_SERVER_IP="YOUR_RANDNET_SERVER_IP"   # LAN IP of this machine
TOMCAT_VERSION="9.0.118"
REVIVAL_REPO="https://github.com/2cans1string/RandnetRevival.git"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ─── Architecture detection ───────────────────────────────────────────────────

ARCH=$(uname -m)
case "$ARCH" in
    aarch64) ARCH_LABEL="ARM64 (aarch64)" ;;
    armv7l)  ARCH_LABEL="ARM32 (armv7l)"  ;;
    x86_64)  ARCH_LABEL="x86_64"          ;;
    *)       ARCH_LABEL="unknown ($ARCH)"  ;;
esac

echo "=================================================="
echo " Randnet 64DD Revival — Full Install"
echo "=================================================="
echo " Architecture : $ARCH_LABEL"
echo " Server IP    : $RANDNET_SERVER_IP"
echo " Tomcat       : $TOMCAT_VERSION"
echo "=================================================="
echo ""

if [ "$RANDNET_SERVER_IP" = "YOUR_RANDNET_SERVER_IP" ]; then
    echo "ERROR: Edit RANDNET_SERVER_IP at the top of this script before running."
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Run as root or with sudo."
    exit 1
fi

# ─── Stage 1: System update + all dependencies ────────────────────────────────
# Install everything before iptables port-80 redirect breaks apt.

echo ""
echo "[1/9] Installing system dependencies..."
apt-get update -y
apt-get install -y \
    openjdk-21-jdk \
    maven \
    git \
    gcc \
    make \
    ppp \
    squid \
    dnsmasq \
    iptables \
    dpkg-dev \
    devscripts \
    python3 \
    wget \
    curl

JAVA_HOME=$(readlink -f /usr/bin/java | sed 's|/bin/java||')
echo "JAVA_HOME detected: $JAVA_HOME"

# ─── Stage 2: pppd CHAP bypass plugin ────────────────────────────────────────

echo ""
echo "[2/9] Building and installing randnet_chap.so..."
cd "$SCRIPT_DIR/pppd_plugin"
make randnet_chap.so
install -m 755 randnet_chap.so /etc/ppp/
echo "  randnet_chap.so → /etc/ppp/"
cd "$SCRIPT_DIR"

# ─── Stage 3: pppd auth_ip_addr patch ────────────────────────────────────────
# pppd's auth_ip_addr() rejects the 64DD's PPP IP because it has no matching
# secrets entry (we use noauth). We patch it to always return 1 (authorized).
# Approach: build pppd from source with a one-line patch, then install.

echo ""
echo "[3/9] Patching pppd auth_ip_addr..."

PPPD_BIN=$(which pppd 2>/dev/null || echo "/usr/sbin/pppd")
PPPD_VER=$("$PPPD_BIN" --version 2>&1 | awk '{print $3}' | tr -d '[:space:]')
echo "  pppd $PPPD_VER at $PPPD_BIN"

BUILD_DIR=$(mktemp -d /tmp/pppd-build.XXXXXX)
PATCHED=0

# Try source build first (reliable, arch-independent)
if apt-get source ppp -y --download-only 2>/dev/null; then
    # Move source files to build dir
    find . -maxdepth 1 -name "ppp_*.dsc" -o -name "ppp_*.tar.*" | xargs -I{} mv {} "$BUILD_DIR/" 2>/dev/null || true
    cd "$BUILD_DIR"

    # Extract
    DSC=$(find . -name "*.dsc" | head -1)
    if [ -n "$DSC" ]; then
        dpkg-source -x "$DSC" src/ 2>/dev/null
        AUTH_C=$(find src -name "auth.c" | grep pppd | head -1)

        if [ -n "$AUTH_C" ]; then
            # Patch: add 'return 1;' as first statement of auth_ip_addr()
            python3 - "$AUTH_C" <<'PYEOF'
import re, sys
path = sys.argv[1]
with open(path) as f:
    src = f.read()
# Match the function definition and insert early return after the opening brace
patched = re.sub(
    r'(auth_ip_addr\s*\([^)]*\)\s*\n\{)',
    r'\1\n    return 1; /* Randnet 64DD: accept any peer IP */',
    src
)
if patched == src:
    # Try older-style K&R definition
    patched = re.sub(
        r'(auth_ip_addr\s*\(unit,\s*addr\)[^\{]*\{)',
        r'\1\n    return 1; /* Randnet 64DD: accept any peer IP */',
        src, flags=re.DOTALL
    )
with open(path, 'w') as f:
    f.write(patched)
print("  auth_ip_addr patched in", path)
PYEOF

            # Build the patched pppd binary
            cd src/
            dpkg-buildpackage -b -uc -us 2>/dev/null && PATCHED=1 || true
            cd ..

            if [ "$PATCHED" -eq 1 ]; then
                PPPD_DEB=$(find . -name "ppp_*.deb" | head -1)
                if [ -n "$PPPD_DEB" ]; then
                    dpkg -i "$PPPD_DEB"
                    echo "  pppd installed from patched source package"
                fi
            fi
        fi
    fi
fi

cd "$SCRIPT_DIR"

# Fall back to binary patch if source build didn't work
if [ "$PATCHED" -eq 0 ]; then
    echo "  Source build unavailable — attempting binary patch..."
    if [ -f "${PPPD_BIN}.orig" ]; then
        echo "  Backup ${PPPD_BIN}.orig already exists — skipping"
    else
        cp "$PPPD_BIN" "${PPPD_BIN}.orig"
    fi

    python3 - "$PPPD_BIN" "$ARCH" <<'PYEOF'
import sys, os

pppd_path = sys.argv[1]
arch      = sys.argv[2]

with open(pppd_path, 'rb') as f:
    data = bytearray(f.read())

# Patterns: "return 0" epilogue for auth_ip_addr, by architecture
patterns = {
    'aarch64': (
        bytes([0x00, 0x00, 0x80, 0x52, 0xC0, 0x03, 0x5F, 0xD6]),  # MOV W0,#0 ; RET
        bytes([0x20, 0x00, 0x80, 0x52, 0xC0, 0x03, 0x5F, 0xD6]),  # MOV W0,#1 ; RET
    ),
    'armv7l': (
        bytes([0x00, 0x00, 0xA0, 0xE3, 0x1E, 0xFF, 0x2F, 0xE1]),  # MOV R0,#0 ; BX LR
        bytes([0x01, 0x00, 0xA0, 0xE3, 0x1E, 0xFF, 0x2F, 0xE1]),  # MOV R0,#1 ; BX LR
    ),
}

if arch not in patterns:
    print(f"  Binary patch not supported for arch {arch} — skipping")
    sys.exit(0)

needle, replacement = patterns[arch]
idx = data.find(needle)
if idx < 0:
    print(f"  Pattern not found in {pppd_path} — manual patch may be required")
    sys.exit(0)

data[idx:idx + len(replacement)] = replacement
with open(pppd_path, 'wb') as f:
    f.write(data)
print(f"  auth_ip_addr patched at offset {idx:#x}")
PYEOF
    PATCHED=$?
fi

rm -rf "$BUILD_DIR"

# ─── Stage 4: Apache Tomcat 9 ─────────────────────────────────────────────────

echo ""
echo "[4/9] Installing Apache Tomcat $TOMCAT_VERSION..."

if ! id tomcat &>/dev/null; then
    useradd -m -U -d /opt/tomcat -s /bin/false tomcat
fi

TOMCAT_TGZ="apache-tomcat-${TOMCAT_VERSION}.tar.gz"
TOMCAT_URL="https://dlcdn.apache.org/tomcat/tomcat-9/v${TOMCAT_VERSION}/bin/${TOMCAT_TGZ}"

wget -q -O "/tmp/${TOMCAT_TGZ}" "$TOMCAT_URL"
mkdir -p /opt/tomcat
tar -xzf "/tmp/${TOMCAT_TGZ}" -C /opt/tomcat --strip-components=1
chown -R tomcat:tomcat /opt/tomcat
chmod -R 755 /opt/tomcat

cat > /etc/systemd/system/tomcat.service <<EOF
[Unit]
Description=Apache Tomcat 9 — Randnet Revival Server
After=network.target

[Service]
Type=forking
User=tomcat
Group=tomcat
Environment="JAVA_HOME=${JAVA_HOME}"
Environment="CATALINA_PID=/opt/tomcat/temp/tomcat.pid"
Environment="CATALINA_HOME=/opt/tomcat"
Environment="CATALINA_BASE=/opt/tomcat"
Environment="CATALINA_OPTS=-Xms256M -Xmx512M -server -XX:+UseParallelGC"
Environment="JAVA_OPTS=-Djava.awt.headless=true -Djava.security.egd=file:/dev/./urandom"
ExecStart=/opt/tomcat/bin/startup.sh
ExecStop=/opt/tomcat/bin/shutdown.sh
SuccessExitStatus=143
RestartSec=10
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable tomcat
systemctl start tomcat
echo "  Tomcat started"

# ─── Stage 5: Build and deploy Randnet servlet WAR ───────────────────────────
# Clone RandnetRevival, inject server IP, build, deploy as ROOT.war.
# Must happen before iptables port-80 redirect (Maven needs internet access).

echo ""
echo "[5/9] Building and deploying Randnet servlet WAR..."

SERVLET_BUILD_DIR=$(mktemp -d /tmp/randnet-servlet.XXXXXX)
git clone --depth=1 "$REVIVAL_REPO" "$SERVLET_BUILD_DIR/repo"

# Inject this machine's IP into GetCommunicationConfigServlet
GSCONFIG="$SERVLET_BUILD_DIR/repo/servlet/src/main/java/jp/ne/randnet/servlet/GetCommunicationConfigServlet.java"
if [ -f "$GSCONFIG" ]; then
    sed -i "s/YOUR_RANDNET_SERVER_IP/$RANDNET_SERVER_IP/g" "$GSCONFIG"
fi

# Build
cd "$SERVLET_BUILD_DIR/repo/servlet"
mvn clean package -q

# Deploy
cp target/randnet.war /opt/tomcat/webapps/ROOT.war
chown tomcat:tomcat /opt/tomcat/webapps/ROOT.war
echo "  ROOT.war deployed to Tomcat"

cd "$SCRIPT_DIR"
rm -rf "$SERVLET_BUILD_DIR"

# Wait for Tomcat to deploy ROOT.war
echo -n "  Waiting for Tomcat deployment"
for i in $(seq 1 15); do
    if curl -s http://localhost:8080/servlet/GetNewVersion | grep -q "RESULT=OK"; then
        echo " OK"
        break
    fi
    echo -n "."
    sleep 2
done

# ─── Stage 6: iptables — port 80 → 8080 + proxy exemption ───────────────────
# Set up AFTER Maven is done.

echo ""
echo "[6/9] Configuring iptables (server-side)..."

iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8080
iptables -t nat -A OUTPUT -p tcp --dport 80 -m owner ! --uid-owner proxy -j REDIRECT --to-port 8080

# DreamPi-side DNAT rules (if ppp0 is present or will be)
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -A FORWARD -i ppp0 -o eth0 -j ACCEPT
iptables -A FORWARD -i eth0 -o ppp0 -m state --state RELATED,ESTABLISHED -j ACCEPT
for RNET_IP in 172.16.10.30 172.16.10.31 172.16.10.40; do
    iptables -t nat -A PREROUTING -i ppp0 -d "$RNET_IP" -j DNAT \
        --to-destination "$RANDNET_SERVER_IP"
done
iptables -t nat -A PREROUTING -i ppp0 -d 172.16.10.41 -p tcp --dport 8080 \
    -j DNAT --to-destination "${RANDNET_SERVER_IP}:3128"

# Persist
mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4

cat > /etc/systemd/system/iptables-restore.service <<'EOF'
[Unit]
Description=Restore iptables rules
Before=network.target

[Service]
Type=oneshot
ExecStart=/sbin/iptables-restore /etc/iptables/rules.v4
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable iptables-restore
echo "  iptables rules saved and will restore on boot"

# ─── Stage 7: Squid proxy ────────────────────────────────────────────────────

echo ""
echo "[7/9] Configuring Squid..."

# Allow 64DD PPP range (10.200.x.x) and local connections
cat > /etc/squid/conf.d/randnet.conf <<'EOF'
acl randnet_ppp src 10.200.0.0/16
http_access allow randnet_ppp
http_access allow localnet
http_access allow all
EOF

systemctl enable squid
systemctl restart squid
echo "  Squid configured on port 3128"

# ─── Stage 8: dnsmasq ────────────────────────────────────────────────────────

echo ""
echo "[8/9] Configuring dnsmasq..."

mkdir -p /etc/dnsmasq.d
cp "$SCRIPT_DIR/etc/dnsmasq.d/randnet.conf" /etc/dnsmasq.d/

# Enable conf-dir if not already active
if [ -f /etc/dnsmasq.conf ]; then
    if grep -q "^#conf-dir=/etc/dnsmasq.d" /etc/dnsmasq.conf; then
        sed -i 's|^#conf-dir=/etc/dnsmasq.d|conf-dir=/etc/dnsmasq.d|' /etc/dnsmasq.conf
    elif ! grep -q "^conf-dir=/etc/dnsmasq.d" /etc/dnsmasq.conf; then
        echo "conf-dir=/etc/dnsmasq.d" >> /etc/dnsmasq.conf
    fi
fi

systemctl enable dnsmasq
systemctl restart dnsmasq
echo "  dnsmasq configured (randnet.ne.jp → 127.0.0.1)"

# ─── Stage 9: IP forwarding ───────────────────────────────────────────────────

echo ""
echo "[9/9] Enabling IP forwarding..."

echo 1 > /proc/sys/net/ipv4/ip_forward

if grep -q "^#*net.ipv4.ip_forward" /etc/sysctl.conf; then
    sed -i 's/^#*net.ipv4.ip_forward.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf
else
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi

# ─── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "=================================================="
echo " Randnet 64DD Revival — Install Complete"
echo "=================================================="
echo ""
echo " Verification:"
echo "   Tomcat servlet: curl http://localhost/servlet/GetNewVersion"
echo "   Squid proxy:    curl -x http://localhost:3128 http://example.com/ | head -3"
echo ""
echo " Next steps:"
echo "   1. Add your disk credentials to CheckMemberServlet.java,"
echo "      rebuild ROOT.war, and deploy to /opt/tomcat/webapps/"
echo "   2. Confirm RANDNET_SERVER_IP=$RANDNET_SERVER_IP in dreampi.py"
echo "   3. Start dreampi: sudo python dreampi.py start"
echo "   4. Watch logs:    sudo tail -f /opt/tomcat/logs/catalina.out"
echo ""
echo " pppd binary: $(which pppd) — backup at $(which pppd).orig (if patched)"
echo "=================================================="
