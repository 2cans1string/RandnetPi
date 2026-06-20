#!/bin/bash
# install_randnet.sh — RandnetPi full stack installer
#
# Installs: pppd 2.4.7 (patched) + CHAP bypass plugin + Tomcat 9 + Squid + dnsmasq
# All Randnet server IPs are routed to localhost — no separate server needed.
#
# Usage: sudo ./install_randnet.sh

set -e

# Run apt and other tooling without interactive prompts
export DEBIAN_FRONTEND=noninteractive

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

# Detect the Pi's real eth0 IP. Randnet DNS targets and DNAT destinations must
# point at this address (NOT 127.0.0.1) — live testing showed loopback targets
# do not work for forwarded ppp0 traffic.
ETH0_IP=$(ip -4 -o addr show eth0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)
[ -n "$ETH0_IP" ] || error "Could not determine eth0 IP address — is eth0 up with an IPv4 address?"
info "Detected eth0 IP: $ETH0_IP"

# ─── STEP 2: Install all required packages ───────────────────────────────────
# All packages must be installed before the port-80 iptables redirect (Step 10)
# blocks HTTP package downloads. Do not move apt commands after Step 9.
#
# The install is split into three steps to break a circular dependency: maven
# pulls in ca-certificates-java, whose postinst deadlocks on Buster if openjdk
# is not yet fully configured. Installing openjdk first (and fixing the deadlock)
# before maven avoids the crash entirely.

info "Updating apt package lists..."
apt-get update -y

# STEP A: everything except openjdk and maven.
info "STEP A: installing base packages (no Java/Maven)..."
apt-get install -y gcc make ppp-dev libpcap-dev git wget curl squid dnsmasq

# STEP B: install openjdk first and clear the Buster ca-certificates-java
# deadlock before maven ever runs.
info "STEP B: installing OpenJDK 11..."
mkdir -p /etc/ssl/certs/java
apt-get install -y openjdk-11-jdk || true
dpkg --configure --force-depends openjdk-11-jre-headless:armhf || true
dpkg --configure ca-certificates-java || true
dpkg --configure -a
apt-get install -f -y

# Verify Java 11 is actually present and working.
if ! java -version 2>&1 | grep -q 'version "11'; then
    echo "ERROR: Java 11 failed to install"
    exit 1
fi
info "Java 11 verified: $(java -version 2>&1 | head -1)"

JAVA_BIN=$(which java 2>/dev/null || readlink -f /usr/bin/java 2>/dev/null || true)
if [ -z "$JAVA_BIN" ]; then
    error "Java installation succeeded but java binary not found on PATH"
fi
JAVA_HOME=$(dirname $(dirname $(readlink -f "$JAVA_BIN")))
if [ "$JAVA_HOME" = "/" ] || [ -z "$JAVA_HOME" ]; then
    error "JAVA_HOME detection produced invalid path: $JAVA_HOME"
fi
echo "JAVA_HOME=${JAVA_HOME}" >> /etc/environment
info "JAVA_HOME=${JAVA_HOME}"

# STEP C: install maven now that ca-certificates-java is fully configured.
info "STEP C: installing Maven..."
apt-get install -y maven

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

# route_localnet=1 allows routing of loopback-range traffic, required for some
# of the local redirect paths used by the Randnet stack.
info "Enabling net.ipv4.conf.all.route_localnet..."
sysctl -w net.ipv4.conf.all.route_localnet=1
if grep -q "^#*net.ipv4.conf.all.route_localnet" /etc/sysctl.conf; then
    sed -i 's/^#*net.ipv4.conf.all.route_localnet.*/net.ipv4.conf.all.route_localnet=1/' /etc/sysctl.conf
else
    echo "net.ipv4.conf.all.route_localnet=1" >> /etc/sysctl.conf
fi
info "route_localnet enabled persistently via sysctl."

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

# pppd loads the plugin by BARE NAME from its compiled-in plugin directory.
# Install to both the prefix=/usr (/usr/lib) and prefix=/usr/local version dirs
# so the plugin is found regardless of how pppd was configured. Do NOT install to
# /etc/ppp — pppd does not search there for bare-name plugins.
for plugdir in "/usr/lib/pppd/${PPPD_VERSION}" "/usr/local/lib/pppd/${PPPD_VERSION}"; do
    mkdir -p "$plugdir"
    install -m 755 "${SCRIPT_DIR}/pppd_plugin/randnet_chap.so" "$plugdir/randnet_chap.so"
    info "randnet_chap.so installed to $plugdir/randnet_chap.so"
done

# ─── STEP 5: Download, patch, and build pppd 2.4.7 ───────────────────────────

info "Downloading pppd ${PPPD_VERSION} source..."
BUILD_DIR=$(mktemp -d /tmp/randnet-pppd.XXXXXX)
PPPD_DOWNLOADED=0
for PPPD_URL in "${PPPD_SRC_URLS[@]}"; do
    info "Trying $PPPD_URL ..."
    if wget -q --timeout=30 --tries=3 -O "${BUILD_DIR}/ppp.tar.gz" "$PPPD_URL" 2>/dev/null; then
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

# Build pppd WITHOUT MS-CHAP and MPPE. Setting CHAPMS= and MPPE= empty stops the
# DES-dependent object pppcrypt.o from being compiled at all — that object is the
# only thing referencing the glibc DES primitives setkey()/encrypt(), which modern
# glibc removed (cause of the "undefined reference to setkey/encrypt" link errors).
# Our CHAP bypass plugin never uses MS-CHAP, so dropping it is the proper fix.
# Some toolchains also need a libcrypto.so dev symlink present at link time.
if [ -e /usr/lib/arm-linux-gnueabihf/libcrypto.so.1.1 ] && \
   [ ! -e /usr/lib/arm-linux-gnueabihf/libcrypto.so ]; then
    ln -s /usr/lib/arm-linux-gnueabihf/libcrypto.so.1.1 /usr/lib/arm-linux-gnueabihf/libcrypto.so
    info "Created libcrypto.so symlink"
fi
info "Building pppd without MS-CHAP/MPPE (CHAPMS= MPPE=)..."
make -C pppd pppd CHAPMS= MPPE= LIBS="-lcrypt -lutil -ldl -lpcap"

if [ -f /usr/sbin/pppd ] && [ ! -f /usr/sbin/pppd.orig ]; then
    cp /usr/sbin/pppd /usr/sbin/pppd.orig
    info "Original pppd backed up to /usr/sbin/pppd.orig"
fi
install -m 755 -o root -g root pppd/pppd /usr/sbin/pppd
info "Patched pppd ${PPPD_VERSION} installed to /usr/sbin/pppd"
cd "$SCRIPT_DIR"
rm -rf "$BUILD_DIR"

# ─── STEP 6: Install Apache Tomcat 9.0.118 ───────────────────────────────────

info "Installing Apache Tomcat ${TOMCAT_VERSION}..."
if ! id tomcat &>/dev/null; then
    useradd -m -U -d /opt/tomcat -s /bin/false tomcat
    info "Created tomcat user"
fi

wget -q --timeout=30 --tries=3 -O "/tmp/apache-tomcat-${TOMCAT_VERSION}.tar.gz" "$TOMCAT_URL" \
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

# ─── STEP 7: Build and deploy ROOT.war ───────────────────────────────────────

SERVLET_DIR="${SCRIPT_DIR}/servlet"
if [ ! -d "$SERVLET_DIR" ]; then
    warning "servlet/ directory not found at $SERVLET_DIR — skipping WAR build"
else
    info "Building ROOT.war from ${SERVLET_DIR}..."
    mvn clean package -f "${SERVLET_DIR}/pom.xml" -q

    # Stop Tomcat (if running) so webapps can be cleanly replaced.
    if systemctl is-active --quiet tomcat 2>/dev/null; then
        info "Stopping Tomcat before deploying webapp..."
        systemctl stop tomcat
        sleep 2
    fi

    # Remove the stock Tomcat webapps so only our Randnet ROOT is served.
    info "Removing stock Tomcat webapps (ROOT, docs, examples, host-manager, manager)..."
    rm -rf /opt/tomcat/webapps/ROOT \
           /opt/tomcat/webapps/docs \
           /opt/tomcat/webapps/examples \
           /opt/tomcat/webapps/host-manager \
           /opt/tomcat/webapps/manager \
           /opt/tomcat/webapps/ROOT.war

    cp "${SERVLET_DIR}/target/ROOT.war" /opt/tomcat/webapps/ROOT.war
    chown tomcat:tomcat /opt/tomcat/webapps/ROOT.war
    info "ROOT.war deployed to /opt/tomcat/webapps/ROOT.war"

    # Restart Tomcat so it expands and serves the freshly deployed ROOT.war.
    systemctl restart tomcat 2>/dev/null \
        && info "Tomcat restarted to load new ROOT.war" \
        || info "Tomcat not started yet — will start in the service step"
fi

# ─── STEP 8: Configure Squid ─────────────────────────────────────────────────

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

# ─── STEP 9: Install dnsmasq config ─────────────────────────────────────────

info "Installing dnsmasq Randnet config (domains -> $ETH0_IP)..."
mkdir -p /etc/dnsmasq.d
# Copy the repo config (which ships a __ETH0_IP__ placeholder) and substitute the
# detected eth0 IP. The address= targets must resolve to the Pi's real eth0 IP
# (where Tomcat/Squid are reachable), NOT 127.0.0.1.
cp "${SCRIPT_DIR}/etc/dnsmasq.d/randnet.conf" /etc/dnsmasq.d/randnet.conf
sed -i "s/__ETH0_IP__/${ETH0_IP}/g" /etc/dnsmasq.d/randnet.conf
if grep -q "__ETH0_IP__" /etc/dnsmasq.d/randnet.conf; then
    error "Failed to substitute eth0 IP into /etc/dnsmasq.d/randnet.conf"
fi
info "dnsmasq Randnet config installed to /etc/dnsmasq.d/randnet.conf"

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

# ─── STEP 10: Apply iptables NAT rules ───────────────────────────────────────
# Applied LAST so all preceding apt/wget/maven downloads are unaffected.

info "Flushing existing nat table and applying Randnet iptables rules..."
iptables -t nat -F

iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
# Port 80 -> 8080 redirect on BOTH PREROUTING (incoming) and OUTPUT (local/Squid).
# The OUTPUT rule (to this Pi's eth0 IP) was the final critical fix: Squid's
# upstream fetches of randnet pages originate locally and traverse OUTPUT.
iptables -t nat -A PREROUTING  -p tcp --dport 80 -j REDIRECT --to-port 8080
iptables -t nat -A OUTPUT      -p tcp --dport 80 -m owner ! --uid-owner proxy -j REDIRECT --to-port 8080
iptables -t nat -A OUTPUT      -p tcp -d "$ETH0_IP" --dport 80 -j REDIRECT --to-ports 8080
# DNAT Randnet server IPs to this Pi's eth0 IP (NOT 127.0.0.1 — loopback targets
# do not work for forwarded ppp0 traffic).
iptables -t nat -A PREROUTING  -i ppp0 -d 172.16.10.41 -p tcp --dport 8080 -j DNAT --to-destination "${ETH0_IP}:3128"
iptables -t nat -A PREROUTING  -i ppp0 -d 172.16.10.40 -p tcp --dport 8080 -j DNAT --to-destination "${ETH0_IP}:3128"
iptables -t nat -A PREROUTING  -i ppp0 -d 172.16.10.30 -p tcp              -j DNAT --to-destination "${ETH0_IP}:8080"
iptables -t nat -A PREROUTING  -i ppp0 -d 172.16.10.31 -p tcp              -j DNAT --to-destination "${ETH0_IP}:8080"

info "iptables NAT rules applied (8 rules, DNAT -> $ETH0_IP)"

# ─── STEP 11: Save iptables and create persistence service ───────────────────

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

# ─── STEP 12: Install first-boot eth0 IP detection service ───────────────────
# On a freshly-flashed image the eth0 IP will differ from this build machine's.
# This service re-points dnsmasq + iptables at the new IP on first boot, once.

info "Installing first-boot eth0 IP service..."
install -m 755 "${SCRIPT_DIR}/etc/randnet-firstboot.sh" /usr/local/bin/randnet-firstboot.sh
cp "${SCRIPT_DIR}/etc/systemd/randnet-firstboot.service" /etc/systemd/system/randnet-firstboot.service
systemctl daemon-reload
systemctl enable randnet-firstboot.service

# Create the state dir and set the done-flag so the service does NOT fire on THIS
# build machine (its config is already correct for the current eth0 IP).
# IMPORTANT for image builders: before creating a distributable image, remove the
# flag so first-boot runs on flashed copies:
#     sudo rm /var/lib/randnet/firstboot-done
mkdir -p /var/lib/randnet
touch /var/lib/randnet/firstboot-done
info "First-boot service installed and enabled (flag set so it skips on this build machine)."

# ─── STEP 13: Deploy patched dreampi module + symlink the service entrypoint ──
# dreampi.py imports sibling modules (dcnow, config_server, netlink, ...), so it
# must live in a module directory alongside them — /home/pi/dreampi. The systemd
# service runs /usr/local/bin/dreampi, which we make a SYMLINK into that dir (not
# a standalone copy) so the module and the entrypoint never drift apart.

DREAMPI_DIR="/home/pi/dreampi"
DREAMPI_BIN="/usr/local/bin/dreampi"

if [ ! -f "${SCRIPT_DIR}/dreampi.py" ]; then
    warning "repo dreampi.py not found at ${SCRIPT_DIR}/dreampi.py — skipping dreampi deploy"
else
    info "Deploying patched dreampi module to ${DREAMPI_DIR}..."
    mkdir -p "$DREAMPI_DIR"

    # Deploy the patched Python modules into the module directory.
    for mod in dreampi.py dcnow.py config_server.py netlink.py bba_bin.py port_forwarding.py; do
        if [ -f "${SCRIPT_DIR}/${mod}" ]; then
            install -m 644 "${SCRIPT_DIR}/${mod}" "${DREAMPI_DIR}/${mod}"
        fi
    done
    chmod 755 "${DREAMPI_DIR}/dreampi.py"

    # Clear any stale compiled bytecode so the new source is used.
    rm -f "${DREAMPI_DIR}"/*.pyc
    info "Deployed dreampi modules and cleared stale .pyc files"

    # Match ownership to the pi user if it exists (stock DreamPi dir owner).
    if id pi >/dev/null 2>&1; then
        chown -R pi:pi "$DREAMPI_DIR"
    fi

    # Back up the original /usr/local/bin/dreampi once (only if it is a real
    # file, not already our symlink), then replace it with a symlink.
    if [ -e "$DREAMPI_BIN" ] && [ ! -L "$DREAMPI_BIN" ] && [ ! -f "${DREAMPI_BIN}.original" ]; then
        cp -p "$DREAMPI_BIN" "${DREAMPI_BIN}.original"
        info "Backed up original dreampi to ${DREAMPI_BIN}.original"
    fi
    mkdir -p "$(dirname "$DREAMPI_BIN")"
    ln -sfn "${DREAMPI_DIR}/dreampi.py" "$DREAMPI_BIN"
    info "Symlinked $DREAMPI_BIN -> ${DREAMPI_DIR}/dreampi.py"

    # Post-deploy verification: grep the DEPLOYED copies (NOT the repo) to confirm
    # the patches actually landed. A stale file or an unflushed .pyc would silently
    # revert behaviour (domain leak / broken 127.0.0.1 DNAT), so fail loudly here
    # rather than discover it during a live 64DD session.
    info "Verifying deployed copies carry the Randnet patches..."
    DEPLOYED_DCNOW="${DREAMPI_DIR}/dcnow.py"
    DEPLOYED_DREAMPI="${DREAMPI_DIR}/dreampi.py"

    grep -qF "Dreamcast Now fully disabled" "$DEPLOYED_DCNOW" \
        || error "STALE DEPLOY: $DEPLOYED_DCNOW lacks the Dreamcast Now disable patch — domain reporting would still leak 64DD domains to the DCNow API. Redeploy the repo dcnow.py and clear *.pyc."

    grep -qF ".format(eth0_ip)" "$DEPLOYED_DREAMPI" \
        || error "STALE DEPLOY: $DEPLOYED_DREAMPI lacks the eth0-IP DNAT patch. Redeploy the repo dreampi.py and clear *.pyc."

    if grep -qF "127.0.0.1:8080" "$DEPLOYED_DREAMPI" || grep -qF "127.0.0.1:3128" "$DEPLOYED_DREAMPI"; then
        error "STALE DEPLOY: $DEPLOYED_DREAMPI still contains broken 127.0.0.1 DNAT targets. Redeploy the repo dreampi.py and clear *.pyc."
    fi

    grep -qF '"-d", eth0_ip, "--dport", "80"' "$DEPLOYED_DREAMPI" \
        || error "STALE DEPLOY: $DEPLOYED_DREAMPI lacks the OUTPUT-chain port-80 redirect (the critical Squid/64DD fix). Redeploy the repo dreampi.py and clear *.pyc."

    info "Deployed copies verified: Dreamcast Now disabled, eth0-IP DNAT + OUTPUT redirect present."
fi

# ─── STEP 14: Enable and start all services ───────────────────────────────────

info "Starting all services..."
systemctl daemon-reload
systemctl enable tomcat squid dnsmasq
systemctl restart dnsmasq
systemctl restart squid
systemctl start tomcat

# Restart dreampi so it picks up the freshly deployed Randnet config.
if systemctl cat dreampi >/dev/null 2>&1; then
    systemctl restart dreampi && info "dreampi service restarted" \
        || warning "dreampi restart failed — check: journalctl -u dreampi -n 50"
else
    warning "dreampi service not installed — start manually: sudo $DREAMPI_BIN --no-daemon"
fi

info "Waiting 5 seconds for Tomcat to initialise..."
sleep 5
if systemctl is-active --quiet tomcat; then
    info "Tomcat is active"
else
    warning "Tomcat does not appear to be running — check: journalctl -u tomcat -n 50"
fi

# ─── STEP 15: Success summary ─────────────────────────────────────────────────

echo ""
echo "=================================================="
echo "  RandnetPi — Installation Complete"
echo "=================================================="
echo ""
echo "  Services:"
printf "    %-12s %s\n" "tomcat"  "$(systemctl is-active tomcat  2>/dev/null || echo unknown)"
printf "    %-12s %s\n" "squid"   "$(systemctl is-active squid   2>/dev/null || echo unknown)"
printf "    %-12s %s\n" "dnsmasq" "$(systemctl is-active dnsmasq 2>/dev/null || echo unknown)"
printf "    %-12s %s\n" "dreampi" "$(systemctl is-active dreampi 2>/dev/null || echo unknown)"
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
printf "    %-10s %s\n" "CHAP"   "/usr/lib/pppd/${PPPD_VERSION}/randnet_chap.so (+ /usr/local/lib/...)"
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
echo "  dreampi:        module in $DREAMPI_DIR, $DREAMPI_BIN -> dreampi.py (logs: journalctl -u dreampi -f)"
echo "                  original backed up to ${DREAMPI_BIN}.original"
echo "=================================================="
