#!/usr/bin/env python
import os
import sys
import time
import hashlib
import requests
import subprocess
import shutil
import urllib2
import urlparse
import logging
import logging.handlers

# CONFIGURATION
BASE_URL = "http://10.200.0.1:50005"
LIST_FILE_URL = BASE_URL + "/files.list"
DREAMPIPE_URL = "https://dreamcastlive.net/files/"

LOCAL_ROOT = os.path.dirname(os.path.abspath(__file__))
UPDATE_DIR = os.path.join(LOCAL_ROOT, 'updates')

VPN_INTERFACE = "tun0"
VPN_TIMEOUT = 2  # seconds to wait for VPN

def detect_raspberry_os_version():
    os_release_path = "/etc/os-release"
    version_id = None

    if os.path.exists(os_release_path):
        with open(os_release_path, "r") as f:
            lines = f.readlines()
        for line in lines:
            line = line.strip()
            if line.startswith("VERSION_CODENAME="):
                version_id = line.split("=")[1].lower()
                break
            elif line.startswith("VERSION="):
                if "buster" in line.lower():
                    version_id = "buster"
                    break
                elif "stretch" in line.lower():
                    version_id = "stretch"
                    break

    if version_id in ("buster", "stretch"):
        return version_id
    else:
        return None

def get_pi_model_number():
    try:
        with open('/proc/device-tree/model', 'r') as f:
            model = f.read().strip()
            # Look for something like "Raspberry Pi 4 Model B"
            if "Raspberry Pi" in model:
                parts = model.split()
                for i, part in enumerate(parts):
                    if part == "Pi" and i + 1 < len(parts):
                        if parts[i + 1].isdigit():
                            return int(parts[i + 1])
        return None
    except Exception:
        return None

def fetch_dcmail_if_new(timeout=3):
    url = DREAMPIPE_URL
    filename = "dcgmail.sh"
   
    headers = {}

    url = urlparse.urljoin(DREAMPIPE_URL, filename)
    local_file = os.path.join('/boot/', filename)
    meta_file = '/var/tmp/.dcmail.meta'

    if os.path.exists(meta_file):
        with open(meta_file, 'r') as f:
            last_modified = f.read().strip()
            if last_modified:
                headers['If-Modified-Since'] = last_modified

    request = urllib2.Request(url, headers=headers)

    try:
        response = urllib2.urlopen(request, timeout=timeout)
        data = response.read()

        # Save new content
        with open(local_file, 'wb') as f:
            f.write(data)

        # Save Last-Modified (if provided)
        last_modified = response.info().get('Last-Modified')
        if last_modified:
            with open(meta_file, 'w') as f:
                f.write(last_modified)

        logger.info("Downloaded new version of dcgmail")
        return True

    except urllib2.HTTPError as e:
        if e.code == 304:
            logger.info("dcgmail is up to date")
            return False
        else:
            logger.warning("Unable to check latest dcgmail")
            return False

    except urllib2.URLError as e:
        logger.warning("Unable to check latest dcgmail")
        return False

    except Exception as e:
        logger.warning("Unable to check latest dcgmail");
        return False

def setup_logger():
    logger = logging.getLogger('fetch_dreampi_updates')
    logger.setLevel(logging.INFO)
    logger.propagate = False

    syslog = logging.handlers.SysLogHandler(address='/dev/log')
    formatter = logging.Formatter('%(name)s %(message)s')
    syslog.setFormatter(formatter)

    logger.addHandler(syslog)
    return logger

logger = setup_logger()

def require_root():
    if os.geteuid() != 0:
        sys.stderr.write("ERROR: This script must be run as root (use sudo).\n")
        sys.exit(1)

def is_vpn_up():
    try:
        p = subprocess.Popen(["ip", "addr", "show", VPN_INTERFACE], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        out, err = p.communicate()
        return "inet " in out
    except Exception:
        return False

def wait_for_vpn(timeout):
    for _ in range(timeout):
        if is_vpn_up():
            return True
        time.sleep(1)
    logger.info("VPN tunnel not detected.")
    return False

def download_file(url, local_path):
    logger.info("Downloading to %s" % (local_path))
    directory = os.path.dirname(local_path)
    if not os.path.exists(directory):
        os.makedirs(directory)
    response = requests.get(url, stream=True, timeout=2)
    response.raise_for_status()
    with open(local_path, "wb") as f:
        for chunk in response.iter_content(chunk_size=8192):
            if chunk:
                f.write(chunk)

def sha256_checksum(file_path):
    sha256 = hashlib.sha256()
    with open(file_path, "rb") as f:
        while True:
            chunk = f.read(8192)
            if not chunk:
                break
            sha256.update(chunk)
    return sha256.hexdigest()

def install_config_file(file_url, target_path, expected_checksum, perm_str=None):
    # Check if file exists and checksum matches
    if os.path.exists(target_path):
        current_checksum = sha256_checksum(target_path)
        if current_checksum.lower() == expected_checksum.lower():
            return
        else:
            backup_path = target_path + ".bak"
            logger.info("[INFO] Updating config %s, backing up to %s" % (target_path, backup_path))
            try:
                shutil.copy2(target_path, backup_path)
            except Exception as e:
                logger.warning("[WARN] Failed to backup %s: %s" % (target_path, e))

    # Download new file
    try:
        download_file(file_url, target_path)
    except Exception as e:
        logger.error("[ERROR] Failed to download file")
        return

    # Set permissions
    try:
        if perm_str:
            perm_int = int(perm_str, 8)
            os.chmod(target_path, perm_int)
            logger.info("[PERMS] Set %s on %s" % (perm_str, target_path))
        else:
            os.chmod(target_path, 0o600)
            logger.info("[PERMS] Set 600 on %s" % target_path)
    except Exception as e:
        logger.warning("[WARN] Failed to set permissions on %s: %s" % (target_path, e))

def sync_file(file_url, local_path, expected_checksum, perm_str=None):
    if os.path.exists(local_path):
        local_checksum = sha256_checksum(local_path)
        if local_checksum.lower() == expected_checksum.lower():
            return
        else:
            logger.warning("[WARN] Checksum mismatch for %s. Re-downloading." % local_path)
    else:
        logger.info("[MISSING] %s does not exist. Downloading." % local_path)

    try:
        download_file(file_url, local_path)
    except Exception as e:
        logger.error("[ERROR] Failed to download file")
        return

    # Set permissions
    try:
        if perm_str:
            perm_int = int(perm_str, 8)
            os.chmod(local_path, perm_int)
            logger.info("[PERMS] Set %s on %s" % (perm_str, local_path))
        else:
            # Default fallback permission for regular files
            os.chmod(local_path, 0o644)
            logger.info("[PERMS] Set 644 on %s" % local_path)
    except Exception as e:
        logger.warning("[WARN] Failed to set permissions on %s: %s" % (local_path, e))

def process_file_list(file_list_content):
    lines = file_list_content.strip().splitlines()
    for line in lines:
        if not line.strip() or line.startswith("#"):
            continue
        parts = line.strip().split()
        if len(parts) < 2:
            logger.info("Skipping malformed line: %s" % line)
            continue

        rel_path = parts[0]
        checksum_entry = parts[1]

        if ":" not in checksum_entry:
            logger.warning("Invalid checksum format in line: %s" % line)
            continue

        expected_checksum = checksum_entry.split(":")[1]

        perm_str = parts[2] if len(parts) >= 3 else None

        file_url = BASE_URL + "/" + rel_path

        if rel_path.startswith("vpn/"):
            filename = os.path.basename(rel_path)
            target_path = os.path.join("/etc/openvpn/client", filename)
            install_config_file(file_url, target_path, expected_checksum, perm_str)
        else:
            local_path = os.path.join(UPDATE_DIR, rel_path)
            sync_file(file_url, local_path, expected_checksum, perm_str)

def main():
    require_root()

    #Check if latest dcgmail is in /boot
    fetch_dcmail_if_new()

    if not wait_for_vpn(VPN_TIMEOUT):
        logger.warning("Exiting: VPN connection not available.")
        return

    logger.info("Fetching file list...")

    try:
        response = requests.get(LIST_FILE_URL, timeout=2)
        response.raise_for_status()
        file_list_content = response.text
        process_file_list(file_list_content)
        logger.info("Done.")
    except Exception as e:
        logger.info("Update server unavailable for the moment")

if __name__ == "__main__":
    main()
