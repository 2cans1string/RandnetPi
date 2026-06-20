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
        def post_update():
            # RandnetPi: DC Now reporting disabled. The original scanned syslog
            # for DNS query[A] lines (including randnet.ne.jp lookups) and POSTed
            # them to the DCNow API. We no-op it so it neither phones home nor
            # interferes with Randnet domain resolution.
            return
            if not self._service._enabled:
                return
            global gameloft
            lines = [ x for x in sh.tail("/var/log/syslog", "-n", "15", _iter=True) ]
            dns_query = None
            for line in lines[::-1]:
                if "query[A]" in line:
                    # We did a DNS lookup, what was it?
                    remainder = line[line.find("query[A]") + len("query[A]"):].strip()
                    domain = remainder.split(" ", 1)[0].strip()
                    dns_query = sha256(domain).hexdigest()
                    
                    #Send monaco/pod/speed just once - Begin
                    if gameloft and "gameloft" in domain: ## already sent, do not send again.
                        dns_query = None
                        break
                    if "gameloft" in domain: ## first read, send.
                        gameloft = True
                        logger.info("Domain sent to DCNow API: " + domain)
                        break
                    #Send monaco/pod/speed just once - End

                    if "appspot" in domain:
                        pass
                    else:
                        logger.info("Domain sent to DCNow API: " + domain)
                        break

            user_agent = 'Mozilla/4.0 (compatible; MSIE 5.5; Windows NT), Dreamcast Now'
            header = { 'User-Agent' : user_agent }
            mac_address = self._service._mac_address
            data = {}
            if dns_query:
                data["dns_query"] = dns_query

            data = urllib.urlencode(data)
            req = urllib2.Request(API_ROOT + UPDATE_END_POINT.format(mac_address=mac_address), data, header)
            urllib2.urlopen(req) # Send POST update

        while self._running:
            try:
                post_update()
            except:
                logger.exception("Couldn't update Dreamcast Now!")
            dcnow_run.wait(UPDATE_INTERVAL)

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
        logger.propagate = False
        # RandnetPi: DC Now domain reporting disabled. We do NOT start the
        # reporting thread, so no syslog DNS scanning or API calls happen and
        # randnet domain lookups are never intercepted. config_server.py still
        # works (it only imports CONFIGURATION_FILE and scan_mac_address).
        logger.info("DC Now reporting disabled (RandnetPi)")
        return

    def go_offline(self):
        global gameloft
        gameloft = False
        # Reporting thread is never started (go_online is a no-op), so guard
        # against a missing thread/event to avoid a crash on disconnect.
        if self._thread is None:
            logger.info("DC Now Session Ended")
            return
        dcnow_run.set()
        self._thread.stop()
        self._thread = None
        logger.info("DC Now Session Ended")
