CC      := gcc
CFLAGS  := -Wall -fPIC -I/usr/include/pppd
LDFLAGS := -shared

# Read installed pppd version
PPP_VERSION := $(shell pppd --version 2>/dev/null | awk '{print $$3}')

# Required version
REQUIRED_VERSION := 2.4.7

# Plugin directory based on required version
PLUGIN_DIR ?= /usr/lib/pppd/$(REQUIRED_VERSION)

all: pap_noempty.so randnet_chap.so

pap_noempty.so: pap_noempty.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $<

randnet_chap.so: randnet_chap.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $<

install: pap_noempty.so randnet_chap.so
	install -d $(PLUGIN_DIR)
	install -m 755 pap_noempty.so $(PLUGIN_DIR)
	install -m 755 randnet_chap.so $(PLUGIN_DIR)
	install -m 755 randnet_chap.so /etc/ppp/

clean:
	rm -f pap_noempty.so randnet_chap.so
