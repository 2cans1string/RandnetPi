# RandnetPi — Installation Guide

## Setup

### 1. Run the installer

```bash
git clone https://github.com/2cans1string/RandnetPi.git
cd RandnetPi
sudo ./install_randnet.sh
```

All services (Tomcat, Squid, dnsmasq) run locally on the Pi and Randnet's
hardcoded server IPs are routed to localhost via iptables — there is no server
IP to configure.

The installer handles:
- pppd CHAP bypass plugin build and install
- pppd `auth_ip_addr` patch (source build or binary patch)
- OpenJDK 11 + Apache Tomcat 9
- Randnet servlet WAR deployment
- iptables rules (port 80 → 8080, DNAT for Randnet IPs)
- Squid proxy
- dnsmasq configuration

### 2. Add your disk credentials (optional)

`CheckMemberServlet` accepts all connections by default. To map specific
accounts to their original Randnet IDSUF, populate `/etc/randnet/accounts.conf`
(format `MEMBERID:MEMBERPW:DISKID:IDSUF`); otherwise a generated fallback IDSUF
is used.

### 3. Start the daemon

```bash
sudo python dreampi.py start
```

## Monitoring

Monitor connections:

```bash
sudo tail -f /opt/tomcat/logs/catalina.out
```
