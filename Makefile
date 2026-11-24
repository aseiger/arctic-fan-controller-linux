# Out-of-tree build for the ARCTIC Fan Controller hwmon driver (USB HID,
# VID 0x3904 / PID 0xF001) on kernels older than v7.2, where it is mainline.
#
#   make              detect kernel features, patch a build copy, compile
#   sudo make install install into /lib/modules/$(uname -r)/extra + depmod + load
#   sudo make uninstall   remove it again
#   make info         show what was detected (paste this in bug reports)
#   make clean
#
# Build against a specific kernel:  make KDIR=/usr/src/linux-headers-6.1.0-53-amd64
# The upstream driver source is never modified; see src/compat.h and patches/.

KDIR ?= /lib/modules/$(shell uname -r)/build
KVER ?= $(shell uname -r)
BUILD ?= build
MODULE := arctic_fan_controller
SRC    := src/arctic_fan_controller.c
PATCH  := patches/0001-remove-prototype-macro.patch

# Immediate expansion: the kbuild sub-make changes directory, so capture the
# absolute repo path now rather than using $(CURDIR) inside the recipe.
THISDIR := $(shell pwd)

# --- probe the target kernel's headers (no version-number guessing) ---------
HAVE_UNALIGNED_HDR := $(wildcard $(KDIR)/include/linux/unaligned.h)
HAVE_KZALLOC_OBJ   := $(shell grep -qs 'devm_kzalloc_obj' $(KDIR)/include/linux/device.h && echo y)
HID_REMOVE_VOID    := $(shell grep -Eq 'void[[:space:]]*\(\*remove\)[[:space:]]*\([[:space:]]*struct hid_device' $(KDIR)/include/linux/hid.h && echo y)

ccflags-y := -I$(THISDIR)/src -include compat.h
ifeq ($(HAVE_UNALIGNED_HDR),)
ccflags-y += -I$(THISDIR)/shim
endif
ifeq ($(HAVE_KZALLOC_OBJ),)
ccflags-y += -DARCTIC_NO_DEVM_KZALLOC_OBJ
endif
ifneq ($(HID_REMOVE_VOID),y)
ccflags-y += -DARCTIC_REMOVE_RETURNS_INT
endif

obj-m += $(MODULE).o

.PHONY: all info prepare modules dkms-build install uninstall clean help

all: modules

$(BUILD)/$(MODULE).c: $(SRC) $(PATCH)
	@mkdir -p $(BUILD)
	@cp $(SRC) $@
	@patch -s -p1 -d $(BUILD) < $(PATCH)
	@echo "  PATCH   $(MODULE).c (remove() prototype)"

modules: $(BUILD)/$(MODULE).c
	@test -d $(KDIR) || { echo "kernel headers not found at $(KDIR) — install linux-headers-$(KVER) or pass KDIR=..."; exit 1; }
	@$(MAKE) -C $(KDIR) M=$(THISDIR)/$(BUILD) modules

# Used by dkms, which builds in place.
dkms-build:
	@$(MAKE) --no-print-directory BUILD=. modules

info:
	@echo "kernel          : $(KVER)"
	@echo "headers         : $(KDIR)"
	@echo "linux/unaligned.h present : $(if $(HAVE_UNALIGNED_HDR),yes (no shim),no  -> -Ishim)"
	@echo "devm_kzalloc_obj present  : $(if $(HAVE_KZALLOC_OBJ),yes (no macro),no  -> -DARCTIC_NO_DEVM_KZALLOC_OBJ)"
	@echo "hid_driver::remove          : $(if $(HID_REMOVE_VOID),void,int -> -DARCTIC_REMOVE_RETURNS_INT)"
	@echo "ccflags-y       : $(ccflags-y)"

install: modules
	@install -d /lib/modules/$(KVER)/extra
	install -m 0644 $(BUILD)/$(MODULE).ko /lib/modules/$(KVER)/extra/
	depmod -a $(KVER)
	@echo "installed. load now with:  sudo modprobe $(MODULE)"
	@echo "or just plug the controller in — udev loads it from the modalias."

uninstall:
	@rmmod $(MODULE) 2>/dev/null || true
	rm -f /lib/modules/$(KVER)/extra/$(MODULE).ko
	depmod -a $(KVER)
	@echo "removed for $(KVER). If you installed via dkms, use: sudo dkms remove $(MODULE)/<ver> --all"

clean:
	@rm -rf $(BUILD)
	@echo "  CLEAN"

help:
	@sed -n '2,12p' Makefile
