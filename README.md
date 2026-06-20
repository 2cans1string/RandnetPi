# RandnetPi
## Nintendo 64DD Randnet online service revival

> A modified DreamPi that revives the original Japanese Randnet dial-up internet service for the Nintendo 64DD (December 1999 - February 2001).

---

## What is this?

This is a fork of [DreamPi](https://github.com/Kazade/dreampi) modified to support the Nintendo 64DD's proprietary PPP/CHAP connection and route traffic to a local Randnet revival server.

The Nintendo 64DD used a dial-up modem and the [Randnet](https://en.wikipedia.org/wiki/Randnet) online service (Japan, 1999–2001). This project revives that service by:

- Accepting the 64DD's non-standard CHAP authentication via a custom pppd plugin
- Routing hardcoded Randnet server IPs to a local revival server via iptables DNAT
- Resolving `*.randnet.ne.jp` domains to localhost via dnsmasq
- Running Apache Tomcat (Randnet servlets) and Squid (proxy) on the same Pi

---

## Hardware Required

- **Raspberry Pi** (target platform Raspberry Pi 4 with DreamPi 2.0.1 Raspbian Buster) with USB modem adapter
- **Nintendo 64** with **64DD** expansion unit
- **Randnet disk** (original Japanese release)

---

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

Monitor connections:

```bash
sudo tail -f /opt/tomcat/logs/catalina.out
```

---

## Network Architecture

```
Nintendo 64DD (28.8kbps dial-up)
     │
     ▼
RandnetPi (Raspberry Pi + USB modem)
  • pppd + randnet_chap.so  — accepts 64DD CHAP auth
  • dnsmasq                 — resolves *.randnet.ne.jp → 127.0.0.1
  • iptables DNAT:
      172.16.10.30 → 127.0.0.1:8080  (Tomcat)
      172.16.10.31 → 127.0.0.1:8080  (Tomcat)
      172.16.10.40:8080 → 127.0.0.1:3128  (Squid)
      172.16.10.41:8080 → 127.0.0.1:3128  (Squid)
  • Apache Tomcat 9         — Randnet servlet endpoints
  • Squid                   — HTTP proxy for 64DD browser
```

---

## Servlet Endpoints

| Endpoint | Purpose |
|---|---|
| `/servlet/CheckMember` | Account authentication |
| `/servlet/GetCommunicationConfig` | Server config delivery |
| `/servlet/GetNewVersion` | Version check |
| `/servlet/CheckCreditPW` | Credit password check |
| `/servlet/UseMail` | Mail service activation |
| `/servlet/ChangeMailPassword` | Mail password change |

---

> **Note — servlet implementation status**
>
> The servlet source in `servlet/` is included and functional. The one
> exception is `GetCommunicationConfig`, which is intentionally not implemented
> (returns `RC=9999`) pending a safe 64DD disk-write solution. All other
> servlets are functional.

---

## Credits

- **[LuigiBlood](https://github.com/LuigiBlood)** — N64DD research and reverse engineering
- **[Psp9x64](https://github.com/Psp9x64/Randnet)** — original Randnet revival groundwork
- **The DD Dev** (Discord) — project development and testing
- **[Kazade](https://github.com/Kazade/dreampi)** — original DreamPi this project is forked from
