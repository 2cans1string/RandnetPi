#!/bin/bash
# install_randnet.sh — RandnetPi full stack installer
#
# Installs: pppd 2.4.7 (patched) + CHAP bypass plugin + Tomcat 9 + Squid + dnsmasq
# All Randnet server IPs are routed to localhost — no separate server needed.
#
# Usage: sudo ./install_randnet.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PPPD_VERSION="2.4.7"
PPPD_SRC_URLS=(
    "https://snapshot.debian.org/archive/debian/20210101T000000Z/pool/main/p/ppp/ppp_${PPPD_VERSION}.orig.tar.gz"
    "https://snapshot.debian.org/archive/debian/20200601T000000Z/pool/main/p/ppp/ppp_${PPPD_VERSION}.orig.tar.gz"
    "https://snapshot.debian.org/archive/debian/20190101T000000Z/pool/main/p/ppp/ppp_${PPPD_VERSION}.orig.tar.gz"
)
TOMCAT_VERSION="9.0.118"
TOMCAT_URL="https://dlcdn.apache.org/tomcat/tomcat-9/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz"

# ─── Output helpers ──────────────────────────────────────────────────────────

info()    { echo "[INFO]    $*"; }
warning() { echo "[WARNING] $*"; }
error()   { echo "[ERROR]   $*" >&2; exit 1; }

# ─── STEP 1: Verify running as root ──────────────────────────────────────────

if [ "$(id -u)" -ne 0 ]; then
    error "Must be run as root. Use: sudo ./install_randnet.sh"
fi
info "Running as root — OK"

# Safety flush - clear any stale NAT rules that could break downloads
info "Flushing any existing NAT rules to ensure clean internet access during install..."
iptables -t nat -F 2>/dev/null || true

# ─── STEP 2: Install all required packages ───────────────────────────────────
# All packages must be installed before the port-80 iptables redirect (Step 11)
# blocks HTTP package downloads. Do not move apt commands after Step 10.

info "Installing all required packages (apt must complete before iptables redirect)..."
apt-get update -y
apt-get install -y \
    gcc make ppp-dev libpam-dev libpcap-dev \
    maven git wget curl squid dnsmasq
info "All packages installed."

# ─── STEP 3: Enable IP forwarding ────────────────────────────────────────────

info "Enabling IP forwarding..."
sysctl -w net.ipv4.ip_forward=1
if grep -q "^#*net.ipv4.ip_forward" /etc/sysctl.conf; then
    sed -i 's/^#*net.ipv4.ip_forward.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf
else
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi
info "IP forwarding enabled persistently via sysctl."

# ─── STEP 4: Compile randnet_chap.so and verify against pppd ────────────────
# No -m32/-m64 flags: on ARM the compiler triple already targets the correct
# word size implicitly. Those flags are x86-only and are rejected by ARM GCC.

info "Compiling randnet_chap.so..."
gcc -fPIC -shared \
    -I /usr/include/pppd \
    -o "${SCRIPT_DIR}/pppd_plugin/randnet_chap.so" \
    "${SCRIPT_DIR}/pppd_plugin/randnet_chap.c"

# Post-compile verification: warn if .so and pppd ELF width differ
PPPD_FILE_OUT=$(file /usr/sbin/pppd 2>/dev/null || echo "unknown")
SO_FILE_OUT=$(file "${SCRIPT_DIR}/pppd_plugin/randnet_chap.so" 2>/dev/null || echo "unknown")
info "pppd:             $PPPD_FILE_OUT"
info "randnet_chap.so:  $SO_FILE_OUT"

PPPD_IS_64=$(echo "$PPPD_FILE_OUT" | grep -cE "64-bit|ELF 64|aarch64" || true)
SO_IS_64=$(echo "$SO_FILE_OUT"     | grep -cE "64-bit|ELF 64|aarch64" || true)

if [ "$PPPD_IS_64" != "$SO_IS_64" ]; then
    warning "Architecture mismatch: pppd and randnet_chap.so have different ELF widths."
    warning "  pppd:            $PPPD_FILE_OUT"
    warning "  randnet_chap.so: $SO_FILE_OUT"
    warning "The CHAP plugin may fail to load at runtime. Check your gcc toolchain."
else
    info "Architecture verified: pppd and randnet_chap.so ELF width match."
fi

install -m 755 "${SCRIPT_DIR}/pppd_plugin/randnet_chap.so" /etc/ppp/randnet_chap.so
info "randnet_chap.so installed to /etc/ppp/randnet_chap.so"

# ─── STEP 5: Download, patch, and build pppd 2.4.7 ───────────────────────────

info "Downloading pppd ${PPPD_VERSION} source..."
BUILD_DIR=$(mktemp -d /tmp/randnet-pppd.XXXXXX)
PPPD_DOWNLOADED=0
for PPPD_URL in "${PPPD_SRC_URLS[@]}"; do
    info "Trying $PPPD_URL ..."
    if wget -q -O "${BUILD_DIR}/ppp.tar.gz" "$PPPD_URL" 2>/dev/null; then
        info "Downloaded pppd source from $PPPD_URL"
        PPPD_DOWNLOADED=1
        break
    else
        warning "Failed: $PPPD_URL"
        rm -f "${BUILD_DIR}/ppp.tar.gz"
    fi
done
[ "$PPPD_DOWNLOADED" -eq 1 ] || error "All pppd source URLs failed — cannot continue"
tar -xzf "${BUILD_DIR}/ppp.tar.gz" -C "$BUILD_DIR"
PPPD_SRC=$(find "$BUILD_DIR" -maxdepth 1 -type d -name "ppp-*" | head -1)
[ -n "$PPPD_SRC" ] || error "Could not find pppd source directory after extraction"
info "Extracted to $PPPD_SRC"

info "Patching auth_ip_addr() to always return 1..."
python3 - "${PPPD_SRC}/pppd/auth.c" <<'PYEOF'
import re, sys
path = sys.argv[1]
with open(path) as f:
    src = f.read()
patched = re.sub(
    r'(auth_ip_addr\s*\([^)]*\)\s*\n\{)',
    r'\1\n    return 1; /* RandnetPi: accept any peer IP */',
    src
)
if patched == src:
    patched = re.sub(
        r'(int\s+auth_ip_addr\b[^{]*\{)',
        r'\1\n    return 1; /* RandnetPi: accept any peer IP */',
        src, flags=re.DOTALL
    )
if patched == src:
    print("ERROR: auth_ip_addr not found in " + path, file=sys.stderr)
    sys.exit(1)
with open(path, 'w') as f:
    f.write(patched)
print("Patched: " + path)
PYEOF

info "Building patched pppd ${PPPD_VERSION}..."
cd "$PPPD_SRC"
./configure --prefix=/usr --quiet
make -j"$(nproc)" -C pppd pppd

if [ -f /usr/sbin/pppd ] && [ ! -f /usr/sbin/pppd.orig ]; then
    cp /usr/sbin/pppd /usr/sbin/pppd.orig
    info "Original pppd backed up to /usr/sbin/pppd.orig"
fi
install -m 755 -o root -g root pppd/pppd /usr/sbin/pppd
info "Patched pppd ${PPPD_VERSION} installed to /usr/sbin/pppd"
cd "$SCRIPT_DIR"
rm -rf "$BUILD_DIR"

# ─── STEP 6: Install Java 11 ─────────────────────────────────────────────────

info "Installing Java 11..."
apt-get install -y openjdk-11-jdk
JAVA_BIN=$(which java 2>/dev/null || readlink -f /usr/bin/java 2>/dev/null || true)
if [ -z "$JAVA_BIN" ]; then
    error "Java installation succeeded but java binary not found on PATH"
fi
JAVA_HOME=$(dirname $(dirname $(readlink -f "$JAVA_BIN")))
if [ "$JAVA_HOME" = "/" ] || [ -z "$JAVA_HOME" ]; then
    error "JAVA_HOME detection produced invalid path: $JAVA_HOME"
fi
echo "JAVA_HOME=${JAVA_HOME}" >> /etc/environment
info "Java 11 installed — JAVA_HOME=${JAVA_HOME}"

# ─── STEP 7: Install Apache Tomcat 9.0.118 ───────────────────────────────────

info "Installing Apache Tomcat ${TOMCAT_VERSION}..."
if ! id tomcat &>/dev/null; then
    useradd -m -U -d /opt/tomcat -s /bin/false tomcat
    info "Created tomcat user"
fi

wget -q -O "/tmp/apache-tomcat-${TOMCAT_VERSION}.tar.gz" "$TOMCAT_URL" \
    || error "Failed to download Tomcat ${TOMCAT_VERSION}"
if systemctl is-active --quiet tomcat 2>/dev/null; then
    info "Stopping running Tomcat instance before reinstall..."
    systemctl stop tomcat
    sleep 2
fi
rm -rf /opt/tomcat
mkdir -p /opt/tomcat
tar -xzf "/tmp/apache-tomcat-${TOMCAT_VERSION}.tar.gz" -C /opt/tomcat --strip-components=1
chown -R tomcat:tomcat /opt/tomcat
chmod -R 755 /opt/tomcat
info "Tomcat ${TOMCAT_VERSION} extracted to /opt/tomcat"

cat > /etc/systemd/system/tomcat.service <<EOF
[Unit]
Description=Apache Tomcat 9 — Randnet Revival Server
After=network.target

[Service]
Type=forking
User=tomcat
Group=tomcat
Environment="JAVA_HOME=$(dirname $(dirname $(readlink -f /usr/bin/java)))"
Environment="CATALINA_PID=/opt/tomcat/temp/tomcat.pid"
Environment="CATALINA_HOME=/opt/tomcat"
Environment="CATALINA_BASE=/opt/tomcat"
Environment="CATALINA_OPTS=-Xms128M -Xmx256M"
Environment="JAVA_OPTS=-Djava.awt.headless=true -Djava.security.egd=file:/dev/./urandom"
ExecStart=/opt/tomcat/bin/startup.sh
ExecStop=/opt/tomcat/bin/shutdown.sh
SuccessExitStatus=143
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
info "Tomcat systemd service written"

# ─── STEP 8: Build and deploy ROOT.war ───────────────────────────────────────

SERVLET_DIR="${SCRIPT_DIR}/servlet"
if [ ! -d "$SERVLET_DIR" ]; then
    warning "servlet/ directory not found at $SERVLET_DIR — skipping WAR build"
else
    info "Building ROOT.war from ${SERVLET_DIR}..."
    mvn clean package -f "${SERVLET_DIR}/pom.xml" -q
    cp "${SERVLET_DIR}/target/ROOT.war" /opt/tomcat/webapps/ROOT.war
    chown tomcat:tomcat /opt/tomcat/webapps/ROOT.war
    info "ROOT.war deployed to /opt/tomcat/webapps/ROOT.war"
fi

# ─── STEP 9: Configure Squid ─────────────────────────────────────────────────

info "Configuring Squid on port 3128..."
cat > /etc/squid/squid.conf <<'EOF'
http_port 3128

acl randnet src 10.200.0.0/16
http_access allow localhost
http_access allow randnet
http_access deny all

cache_mem 16 MB
access_log /var/log/squid/access.log
EOF
info "Squid configured (allowing localhost and 10.200.0.0/16)"

# ─── STEP 10: Install dnsmasq config ─────────────────────────────────────────

info "Installing dnsmasq Randnet config..."
mkdir -p /etc/dnsmasq.d
cp "${SCRIPT_DIR}/etc/dnsmasq.d/randnet.conf" /etc/dnsmasq.d/randnet.conf

if [ -f /etc/dnsmasq.conf ]; then
    if grep -q "^#conf-dir=/etc/dnsmasq.d" /etc/dnsmasq.conf; then
        sed -i 's|^#conf-dir=/etc/dnsmasq.d|conf-dir=/etc/dnsmasq.d|' /etc/dnsmasq.conf
        info "Enabled conf-dir=/etc/dnsmasq.d in /etc/dnsmasq.conf"
    elif ! grep -q "^conf-dir=/etc/dnsmasq.d" /etc/dnsmasq.conf; then
        echo "conf-dir=/etc/dnsmasq.d" >> /etc/dnsmasq.conf
        info "Added conf-dir=/etc/dnsmasq.d to /etc/dnsmasq.conf"
    fi
else
    echo "conf-dir=/etc/dnsmasq.d" > /etc/dnsmasq.conf
    info "Created /etc/dnsmasq.conf with conf-dir=/etc/dnsmasq.d"
fi
info "dnsmasq Randnet config installed"

# ─── STEP 11: Apply iptables NAT rules ───────────────────────────────────────
# Applied LAST so all preceding apt/wget/maven downloads are unaffected.

info "Flushing existing nat table and applying Randnet iptables rules..."
iptables -t nat -F

iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -t nat -A PREROUTING  -p tcp --dport 80 -j REDIRECT --to-port 8080
iptables -t nat -A OUTPUT      -p tcp --dport 80 -m owner ! --uid-owner proxy -j REDIRECT --to-port 8080
iptables -t nat -A PREROUTING  -i ppp0 -d 172.16.10.41 -p tcp --dport 8080 -j DNAT --to-destination 127.0.0.1:3128
iptables -t nat -A PREROUTING  -i ppp0 -d 172.16.10.40 -p tcp --dport 8080 -j DNAT --to-destination 127.0.0.1:3128
iptables -t nat -A PREROUTING  -i ppp0 -d 172.16.10.30 -p tcp              -j DNAT --to-destination 127.0.0.1:8080
iptables -t nat -A PREROUTING  -i ppp0 -d 172.16.10.31 -p tcp              -j DNAT --to-destination 127.0.0.1:8080

info "iptables NAT rules applied (7 rules)"

# ─── STEP 12: Save iptables and create persistence service ───────────────────

info "Saving iptables rules to /etc/iptables/rules.v4..."
mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4

cat > /etc/systemd/system/iptables-restore.service <<'EOF'
[Unit]
Description=Restore iptables rules on boot
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
systemctl start iptables-restore
info "iptables persistence service enabled and started"

# ─── STEP 13: Enable and start all services ───────────────────────────────────

info "Starting all services..."
systemctl daemon-reload
systemctl enable tomcat squid dnsmasq
systemctl restart dnsmasq
systemctl restart squid
systemctl start tomcat

info "Waiting 5 seconds for Tomcat to initialise..."
sleep 5
if systemctl is-active --quiet tomcat; then
    info "Tomcat is active"
else
    warning "Tomcat does not appear to be running — check: journalctl -u tomcat -n 50"
fi

# ─── STEP 14: Success summary ─────────────────────────────────────────────────

echo ""
echo "=================================================="
echo "  RandnetPi — Installation Complete"
echo "=================================================="
echo ""
echo "  Services:"
printf "    %-12s %s\n" "tomcat"  "$(systemctl is-active tomcat  2>/dev/null || echo unknown)"
printf "    %-12s %s\n" "squid"   "$(systemctl is-active squid   2>/dev/null || echo unknown)"
printf "    %-12s %s\n" "dnsmasq" "$(systemctl is-active dnsmasq 2>/dev/null || echo unknown)"
echo ""
echo "  Test URLs:"
echo "    curl http://localhost:8080/servlet/GetNewVersion"
echo "    curl http://localhost/servlet/GetNewVersion       (via :80 → :8080 redirect)"
echo "    curl -x http://localhost:3128 http://www.randnetdd.co.jp/"
echo ""
echo "  Monitor logs:"
echo "    sudo tail -f /opt/tomcat/logs/catalina.out"
echo "    sudo tail -f /var/log/squid/access.log"
echo "    sudo journalctl -u tomcat -f"
echo ""
echo "  Installed:"
printf "    %-10s %s\n" "pppd"   "/usr/sbin/pppd (${PPPD_VERSION} patched — original: /usr/sbin/pppd.orig)"
printf "    %-10s %s\n" "CHAP"   "/etc/ppp/randnet_chap.so"
printf "    %-10s %s\n" "Java"   "${JAVA_HOME}"
printf "    %-10s %s\n" "Tomcat" "/opt/tomcat (${TOMCAT_VERSION})"
printf "    %-10s %s\n" "Squid"  "port 3128"
printf "    %-10s %s\n" "dnsmasq" "*.randnet.ne.jp + *.randnetdd.co.jp → 127.0.0.1"
echo ""
echo "  iptables NAT rules:"
echo "    POSTROUTING: MASQUERADE on eth0"
echo "    PREROUTING:  :80 → :8080 (all incoming)"
echo "    OUTPUT:      :80 → :8080 (local, excluding proxy)"
echo "    PREROUTING:  172.16.10.40-41:8080 → 127.0.0.1:3128 (Squid)"
echo "    PREROUTING:  172.16.10.30-31:80   → 127.0.0.1:8080 (Tomcat)"
echo ""
echo "  WARNING: apt will no longer work over plain HTTP due to the"
echo "           port 80 → 8080 redirect. To temporarily restore:"
echo "             sudo iptables -t nat -F"
echo "           To re-apply after:"
echo "             sudo iptables-restore /etc/iptables/rules.v4"
echo ""
echo "  Start dreampi:  sudo python ${SCRIPT_DIR}/dreampi.py start"
echo "=================================================="
