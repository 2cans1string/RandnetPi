CC      := gcc
CFLAGS  := -Wall -fPIC -I/usr/include/pppd
LDFLAGS := -shared

SRC     := pap_noempty.c
TARGET  := pap_noempty.so

# Read installed pppd version
PPP_VERSION := $(shell pppd --version 2>/dev/null | awk '{print $$3}')

# Required version
REQUIRED_VERSION := 2.4.7

# Plugin directory based on required version
PLUGIN_DIR ?= /usr/lib/pppd/$(REQUIRED_VERSION)

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $<

install: $(TARGET)
	install -d $(PLUGIN_DIR)
	install -m 755 $(TARGET) $(PLUGIN_DIR)

clean:
	rm -f $(TARGET)

