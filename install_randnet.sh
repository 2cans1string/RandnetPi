#!/bin/bash
# install_randnet.sh — Full RandnetPi installer
#
# Installs the complete Randnet 64DD revival stack on a single Raspberry Pi:
#   pppd 2.4.7 (patched) + CHAP bypass plugin + Tomcat 9 + Squid + dnsmasq
#
# All Randnet server IPs are routed to localhost — no separate server needed.
#
# Usage: sudo ./install_randnet.sh

set -e

TOMCAT_VERSION="9.0.118"
PPPD_VERSION="2.4.7"
PPPD_SRC_URLS=(
    "http://deb.debian.org/debian/pool/main/p/ppp/ppp_${PPPD_VERSION}.orig.tar.gz"
    "http://archive.debian.org/debian/pool/main/p/ppp/ppp_${PPPD_VERSION}.orig.tar.gz"
)
TOMCAT_URL="https://archive.apache.org/dist/tomcat/tomcat-9/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Run as root or with sudo."
    exit 1
fi

# ─── Architecture detection via file /usr/sbin/pppd ──────────────────────────

PPPD_BIN=$(command -v pppd 2>/dev/null || echo "/usr/sbin/pppd")
FILE_OUT=$(file "$PPPD_BIN" 2>/dev/null || echo "unknown")

if echo "$FILE_OUT" | grep -qi "aarch64"; then
    ARCH="aarch64"
    MARCH_FLAG="-march=armv8-a"
elif echo "$FILE_OUT" | grep -qi "ARM"; then
    ARCH="armv7l"
    MARCH_FLAG="-march=armv7-a"
elif echo "$FILE_OUT" | grep -qi "x86-64"; then
    ARCH="x86_64"
    MARCH_FLAG="-march=x86-64"
else
    ARCH="unknown"
    MARCH_FLAG=""
    echo "WARNING: Unrecognised architecture — compiling without -march flag"
fi

echo "=================================================="
echo " RandnetPi — Full Stack Installer"
echo "=================================================="
echo " Architecture : $ARCH  ($FILE_OUT)"
echo " pppd source  : $PPPD_VERSION (Debian archive)"
echo " Tomcat       : $TOMCAT_VERSION"
echo "=================================================="
echo ""

# ─── Stage 1: System dependencies ────────────────────────────────────────────
# All packages installed before port-80 iptables redirect so apt stays intact.

echo "[1/9] Installing system dependencies..."
apt-get update -y
apt-get install -y \
    openjdk-21-jdk \
    maven \
    gcc \
    make \
    build-essential \
    libssl-dev \
    libpam0g-dev \
    ppp \
    squid \
    dnsmasq \
    iptables \
    python3 \
    file \
    wget \
    curl

JAVA_HOME=$(readlink -f /usr/bin/java | sed 's|/bin/java||')
echo "  JAVA_HOME: $JAVA_HOME"

# ─── Stage 2: Download pppd 2.4.7 source from Debian archive ─────────────────

echo ""
echo "[2/9] Downloading pppd ${PPPD_VERSION} source..."
BUILD_DIR=$(mktemp -d /tmp/randnet-build.XXXXXX)

DOWNLOADED=0
for URL in "${PPPD_SRC_URLS[@]}"; do
    echo "  Trying $URL"
    if wget -q -O "${BUILD_DIR}/ppp.tar.gz" "$URL"; then
        DOWNLOADED=1
        break
    fi
done

if [ "$DOWNLOADED" -eq 0 ]; then
    echo "ERROR: Could not download pppd ${PPPD_VERSION} source."
    exit 1
fi

tar -xzf "${BUILD_DIR}/ppp.tar.gz" -C "$BUILD_DIR"
PPPD_SRC=$(find "$BUILD_DIR" -maxdepth 1 -type d -name "ppp-*" | head -1)

if [ -z "$PPPD_SRC" ]; then
    echo "ERROR: Could not find pppd source directory after extraction."
    exit 1
fi
echo "  Extracted to $PPPD_SRC"

# ─── Stage 3: Compile randnet_chap.so ────────────────────────────────────────
# Build against pppd 2.4.7 headers so the plugin ABI matches the binary
# we're about to install.

echo ""
echo "[3/9] Compiling randnet_chap.so (arch: $ARCH)..."
gcc $MARCH_FLAG -fPIC -shared \
    -I "${PPPD_SRC}/pppd" \
    -o "${SCRIPT_DIR}/pppd_plugin/randnet_chap.so" \
    "${SCRIPT_DIR}/pppd_plugin/randnet_chap.c"
install -m 755 "${SCRIPT_DIR}/pppd_plugin/randnet_chap.so" /etc/ppp/
echo "  randnet_chap.so → /etc/ppp/"

# ─── Stage 4: Patch auth_ip_addr() and compile pppd ─────────────────────────
# pppd rejects the 64DD's PPP peer IP because it has no matching secrets entry.
# Patching auth_ip_addr() to always return 1 accepts any peer IP.

echo ""
echo "[4/9] Patching and compiling pppd ${PPPD_VERSION}..."

AUTH_C="${PPPD_SRC}/pppd/auth.c"

python3 - "$AUTH_C" <<'PYEOF'
import re, sys
path = sys.argv[1]
with open(path) as f:
    src = f.read()
# Insert 'return 1;' as the first statement in auth_ip_addr()
patched = re.sub(
    r'(auth_ip_addr\s*\([^)]*\)\s*\n\{)',
    r'\1\n    return 1; /* Randnet 64DD: accept any peer IP */',
    src
)
if patched == src:
    patched = re.sub(
        r'(int\s+auth_ip_addr\b[^{]*\{)',
        r'\1\n    return 1; /* Randnet 64DD: accept any peer IP */',
        src, flags=re.DOTALL
    )
if patched == src:
    print("ERROR: auth_ip_addr pattern not found in", path, file=sys.stderr)
    sys.exit(1)
with open(path, 'w') as f:
    f.write(patched)
print("  auth_ip_addr patched in", path)
PYEOF

cd "${PPPD_SRC}"
./configure --prefix=/usr --quiet
make -j"$(nproc)" -C pppd pppd
install -m 755 -o root -g root pppd/pppd /usr/sbin/pppd
echo "  Patched pppd ${PPPD_VERSION} installed to /usr/sbin/pppd"
cd "$SCRIPT_DIR"

# ─── Stage 5: Apache Tomcat 9 ────────────────────────────────────────────────

echo ""
echo "[5/9] Installing Apache Tomcat ${TOMCAT_VERSION}..."

if ! id tomcat &>/dev/null; then
    useradd -m -U -d /opt/tomcat -s /bin/false tomcat
fi

wget -q -O "/tmp/apache-tomcat-${TOMCAT_VERSION}.tar.gz" "$TOMCAT_URL"
mkdir -p /opt/tomcat
tar -xzf "/tmp/apache-tomcat-${TOMCAT_VERSION}.tar.gz" -C /opt/tomcat --strip-components=1
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

# ─── Stage 6: Build and deploy ROOT.war ──────────────────────────────────────
# Build from local servlet/ directory — no external repo clone needed.
# Must run before stage 7 iptables redirect so Maven can reach the internet.

echo ""
echo "[6/9] Building ROOT.war from ${SCRIPT_DIR}/servlet/..."
cd "${SCRIPT_DIR}/servlet"
mvn clean package -q
cp target/ROOT.war /opt/tomcat/webapps/ROOT.war
chown tomcat:tomcat /opt/tomcat/webapps/ROOT.war
echo "  ROOT.war deployed"

echo -n "  Waiting for Tomcat to deploy ROOT.war"
for i in $(seq 1 20); do
    if curl -sf http://localhost:8080/servlet/GetNewVersion | grep -q "RESULT=OK"; then
        echo " OK"
        break
    fi
    echo -n "."
    sleep 2
done
cd "$SCRIPT_DIR"

# ─── Stage 7: iptables rules ─────────────────────────────────────────────────
# Applied AFTER Maven so port-80 redirect does not break package downloads.

echo ""
echo "[7/9] Configuring iptables..."

# Port 80 → 8080 (Tomcat) for all incoming and locally-generated traffic
iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8080
iptables -t nat -A OUTPUT -p tcp --dport 80 -m owner ! --uid-owner proxy \
    -j REDIRECT --to-port 8080

# MASQUERADE for PPP → eth0
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# DNAT 172.16.10.41:8080 and 172.16.10.40:8080 → Squid on localhost:3128
for RNET_IP in 172.16.10.41 172.16.10.40; do
    iptables -t nat -A PREROUTING -i ppp0 -d "$RNET_IP" -p tcp --dport 8080 \
        -j DNAT --to-destination 127.0.0.1:3128
done

# DNAT 172.16.10.30 and 172.16.10.31 → Tomcat on localhost:8080
for RNET_IP in 172.16.10.30 172.16.10.31; do
    iptables -t nat -A PREROUTING -i ppp0 -d "$RNET_IP" \
        -j DNAT --to-destination 127.0.0.1:8080
done

# Persist rules so they survive reboot
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
echo "  iptables rules applied and persisted via systemd"

# ─── Stage 8: Squid proxy ────────────────────────────────────────────────────

echo ""
echo "[8/9] Configuring Squid on port 3128..."

cat > /etc/squid/conf.d/randnet.conf <<'EOF'
acl randnet_ppp src 10.200.0.0/16
http_access allow randnet_ppp
http_access allow localnet
http_access allow all
EOF

systemctl enable squid
systemctl restart squid
echo "  Squid configured on port 3128"

# ─── Stage 9: dnsmasq + IP forwarding + accounts config ──────────────────────

echo ""
echo "[9/9] Configuring dnsmasq, IP forwarding, and accounts..."

mkdir -p /etc/dnsmasq.d
cp "${SCRIPT_DIR}/etc/dnsmasq.d/randnet.conf" /etc/dnsmasq.d/

if [ -f /etc/dnsmasq.conf ]; then
    if grep -q "^#conf-dir=/etc/dnsmasq.d" /etc/dnsmasq.conf; then
        sed -i 's|^#conf-dir=/etc/dnsmasq.d|conf-dir=/etc/dnsmasq.d|' /etc/dnsmasq.conf
    elif ! grep -q "^conf-dir=/etc/dnsmasq.d" /etc/dnsmasq.conf; then
        echo "conf-dir=/etc/dnsmasq.d" >> /etc/dnsmasq.conf
    fi
fi

systemctl enable dnsmasq
systemctl restart dnsmasq
echo "  dnsmasq configured (*.randnet.ne.jp → 127.0.0.1)"

echo 1 > /proc/sys/net/ipv4/ip_forward
if grep -q "^#*net.ipv4.ip_forward" /etc/sysctl.conf; then
    sed -i 's/^#*net.ipv4.ip_forward.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf
else
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi
echo "  IP forwarding enabled"

mkdir -p /etc/randnet
if [ ! -f /etc/randnet/accounts.conf ]; then
    cp "${SCRIPT_DIR}/etc/randnet/accounts.conf.example" /etc/randnet/accounts.conf
    echo "  Created /etc/randnet/accounts.conf — edit before connecting"
fi

# ─── Cleanup + summary ───────────────────────────────────────────────────────

rm -rf "$BUILD_DIR"

echo ""
echo "=================================================="
echo " RandnetPi — Install Complete"
echo "=================================================="
echo ""
echo " Verification:"
echo "   Servlet:  curl http://localhost/servlet/GetNewVersion"
echo "   Squid:    curl -x http://localhost:3128 http://example.com/ | head -3"
echo ""
echo " Next steps:"
echo "   1. Edit /etc/randnet/accounts.conf with your Randnet disk credentials"
echo "   2. Start dreampi: sudo python ${SCRIPT_DIR}/dreampi.py start"
echo "   3. Watch logs:    sudo tail -f /opt/tomcat/logs/catalina.out"
echo ""
echo " pppd:  /usr/sbin/pppd (patched — auth_ip_addr always returns 1)"
echo " CHAP:  /etc/ppp/randnet_chap.so"
echo "=================================================="
