#!/bin/bash
# randnet-firstboot.sh
#
# Runs ONCE on the first boot of a freshly-flashed RandnetPi image to re-point
# the dnsmasq config and iptables rules at THIS machine's eth0 IP, which will
# differ from the build machine's. After it succeeds it drops a flag file and
# disables itself so it never runs again.
#
# IMAGE BUILDERS: install_randnet.sh touches /var/lib/randnet/firstboot-done so
# this does NOT fire on the build machine (its config is already correct). Before
# creating a distributable image, remove that flag so first-boot runs on flashed
# copies:   sudo rm /var/lib/randnet/firstboot-done

set -e

FLAG=/var/lib/randnet/firstboot-done
DNSMASQ_CONF=/etc/dnsmasq.d/randnet.conf
RULES=/etc/iptables/rules.v4

log() { echo "[randnet-firstboot] $*"; }

# Already configured? Nothing to do.
if [ -f "$FLAG" ]; then
    log "Flag $FLAG present — already configured, exiting."
    exit 0
fi

# 1. Detect eth0 IP, waiting up to 30s (15 x 2s) for DHCP / link-up.
ETH0_IP=""
for i in $(seq 1 15); do
    ETH0_IP=$(ip -4 -o addr show eth0 | awk '{print $4}' | cut -d/ -f1)
    if [ -n "$ETH0_IP" ]; then
        break
    fi
    log "eth0 has no IP yet (attempt ${i}/15) — waiting 2s..."
    sleep 2
done
if [ -z "$ETH0_IP" ]; then
    log "ERROR: eth0 still has no IP after 30s — aborting."
    exit 1
fi
log "Detected eth0 IP: $ETH0_IP"

# 2. Re-point the dnsmasq Randnet config at this IP (replace the IP on the
#    address= lines, not the whole file). Handles both an unsubstituted
#    __ETH0_IP__ placeholder and a previously-baked IP.
if [ -f "$DNSMASQ_CONF" ]; then
    sed -i "s/__ETH0_IP__/${ETH0_IP}/g" "$DNSMASQ_CONF"
    sed -i -E "s#(^address=/[^/]+/)[0-9.]+#\1${ETH0_IP}#" "$DNSMASQ_CONF"
    log "Updated $DNSMASQ_CONF"
fi

# 3 + 4. Re-point and persist the iptables rules. Only the OLD eth0 IP (taken
#    from the --to-destination targets) is replaced, so the fixed Randnet server
#    IPs (172.16.10.x) are left untouched.
if [ -f "$RULES" ]; then
    OLD_IP=$(grep -oE '\-\-to-destination [0-9.]+' "$RULES" | awk '{print $2}' | head -1)
    if [ -n "$OLD_IP" ] && [ "$OLD_IP" != "$ETH0_IP" ]; then
        OLD_IP_ESC=$(echo "$OLD_IP" | sed 's/\./\\./g')
        sed -i "s/${OLD_IP_ESC}/${ETH0_IP}/g" "$RULES"
        log "Replaced old IP $OLD_IP with $ETH0_IP in $RULES"
    fi
    iptables-restore < "$RULES"
    log "Reapplied iptables rules from $RULES"
fi

# 5. Restart services so they pick up the new IP. dreampi is ordered After this
#    unit (Before=dreampi), so use --no-block to avoid a start-job deadlock; it
#    will start with the fresh config regardless.
systemctl restart dnsmasq || log "WARNING: dnsmasq restart failed"
systemctl restart --no-block dreampi || log "WARNING: dreampi restart failed"

# 6. Drop the flag so this never runs again.
mkdir -p "$(dirname "$FLAG")"
touch "$FLAG"
log "Created flag $FLAG"

# 7. Disable self.
systemctl disable randnet-firstboot.service || log "WARNING: could not disable randnet-firstboot.service"

log "First-boot configuration complete (eth0 IP: ${ETH0_IP})."
