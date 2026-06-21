# RandnetPi

Revival of the Nintendo 64DD Randnet online service (December 1999 – February 2001) on a Raspberry Pi.

## Getting Started
→ [Installation Guide](INSTALL.md)

## Compatibility
- Raspberry Pi Zero, 1, 2, 3, 3B+ — tested
- Raspberry Pi 4 — tested
- Raspberry Pi 5 — NOT supported (DreamPi incompatible)
- SD card: 8GB minimum
- Requires: USB modem compatible with DreamPi, Nintendo 64 with 64DD, original Randnet disk

## Testers and Hardware Wanted
RandnetPi has been tested on Pi 3B+ and Pi 4. We are looking for people to test on additional hardware:

- Pi Zero / Zero W / Zero 2 W
- Pi 1 / Pi 2B
- Different USB modems

If you test RandnetPi on any hardware not listed above, please open an issue or pull request with your results. We are also interested in hearing from anyone with:
- Additional Randnet disks (registered or unregistered)
- 64DD development hardware
- Knowledge of undocumented Randnet API endpoints

## Research & Discoveries

This project involved analysis of original Randnet disk images and live 64DD hardware responses to reverse-engineer the Randnet servlet API.

### Disk Analysis
- Two NDD disk images were analysed: DDDiskR-DRDJ0-0.ndd (V0, registered) and NUD-DRDJ01-JPN.ndd (V1, unregistered/blank)
- The registered disk contained stored account credentials, CHAP keys, hardcoded server IPs (172.16.10.30–172.16.10.41), and personal emails from February–April 2000
- Network config is written to physical disk at offsets 0x3C2649E and 0x3DCCA1E during registration
- The 64DD uses ACCESS PPP 1.3a with proprietary CHAP authentication requiring both a pppd plugin bypass and a patched auth_ip_addr() function
- All 64DD HTTP traffic is routed through a hardcoded proxy at 172.16.10.41:8080

### Servlet API
Six servlets were identified and implemented from live 64DD traffic analysis:
- `CheckMember` — member authentication
- `GetCommunicationConfig` — network config writer (deliberately frozen at RC=9999 to prevent disk corruption until a disk restoration tool is available)
- `GetNewVersion` — firmware/version check
- `CheckCreditPW` — credit/payment password verification
- `UseMail` — mail access
- `ChangeMailPassword` — mail password change

### Development Disk (BD113)
A Randnet development disk (BD113 — Communication Library Verification Tool, built 1999-09-28) was identified at 64dd.org. This disk systematically tests Randnet API features and may reveal additional API calls not seen in retail disk traffic. Testing against RandnetPi is planned.

### Registration Flow
Blank disk registration is partially implemented — the disk successfully registers via GetCommunicationConfig but the network config fields are not written back to physical media. Resolving this requires a tool capable of writing 64DD disk images back to physical disks (SummerCart64 is the current candidate).

## Services
- Apache Tomcat 9 — Randnet servlet backend
- Squid proxy — 64DD HTTP proxy on port 3128
- dnsmasq — resolves *.randnet.ne.jp and *.randnetdd.co.jp to the Pi
- DreamPi (patched) — PPP dial-up with Randnet CHAP bypass

## Credits
- DreamPi by Kazade (dreamcastlive.net) — the dial-up revival platform RandnetPi is built on
- LuigiBlood (64dd.org) — 64DD preservation, disk image research, and documentation
- Hard4Games — 64DD hardware and testing
- Psp9x64 — Randnet revival research
- The DD Dev — Randnet revival research
- GamingLegend64 and ConsoleVariations — Randnet development disk dumps
