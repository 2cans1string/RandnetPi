#!/usr/bin/env python
#dcnow.py_version=202512152004
import threading
import os
import json
import time
import logging
import urllib
import urllib2
import sh

from hashlib import sha256

from uuid import getnode as get_mac

logger = logging.getLogger('dcnow')

API_ROOT = "https://dcnow-2016.appspot.com"
UPDATE_END_POINT = "/api/update/{mac_address}/"

UPDATE_INTERVAL = 15

CONFIGURATION_FILE = os.path.expanduser("~/.dreampi.json")
gameloft = False

def scan_mac_address():
    mac = get_mac()
    return sha256(':'.join(("%012X" % mac)[i:i+2] for i in range(0, 12, 2))).hexdigest()

class DreamcastNowThread(threading.Thread):
    def __init__(self, service):
        self._service = service
        self._running = True
        super(DreamcastNowThread, self).__init__()

    def run(self):
        # RandnetPi: Dreamcast Now fully disabled. The original scanned syslog for
        # DNS query[A] lines (the 64DD's visited domains) and POSTed them to the
        # external DCNow API via urllib2.urlopen -- that leaked browsing domains and
        # crashed with SSL timeouts. The thread now does nothing.
        return

    def stop(self):
        self._running = False
        self.join()


class DreamcastNowService(object):
    def __init__(self):
        self._thread = None
        self._mac_address = None
        self._enabled = True
        self.reload_settings()

        logger.setLevel(logging.INFO)
        handler = logging.handlers.SysLogHandler(address='/dev/log')
        logger.addHandler(handler)
        formatter = logging.Formatter('%(name)s[%(process)d]: %(message)s')
        handler.setFormatter(formatter)

    def update_mac_address(self, dreamcast_ip):
        self._mac_address = scan_mac_address()
        logger.info("MAC address: {}".format(self._mac_address))

    def reload_settings(self):
        settings_file = CONFIGURATION_FILE

        if os.path.exists(settings_file):
            with open(settings_file, "r") as settings:
                content = json.loads(settings.read())
                self._enabled = content["enabled"]

    def go_online(self, dreamcast_ip):
        # RandnetPi: safe no-op. Accepts dreamcast_ip for signature compatibility
        # but starts NO reporting thread and sends NO network updates, so the
        # 64DD's visited domains are never scanned or sent to the DCNow API.
        # config_server.py still works (it only imports CONFIGURATION_FILE and
        # scan_mac_address).
        logger.propagate = False
        logger.info("Dreamcast Now disabled (RandnetPi)")

    def go_offline(self):
        # RandnetPi: safe no-op. No thread was ever started, so there is nothing
        # to stop and no network teardown to perform.
        global gameloft
        gameloft = False
        logger.info("Dreamcast Now disabled (RandnetPi)")
