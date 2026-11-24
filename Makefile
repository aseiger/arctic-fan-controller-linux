# Out-of-tree build for the ARCTIC Fan Controller hwmon driver (USB HID,
# VID 0x3904 / PID 0xF001) on kernels older than v7.2, where it is mainline.
#
#   make                 detect kernel features, patch a build copy, compile
#   sudo make install    install into /lib/modules/$(uname -r)/extra + depmod
#   sudo make uninstall  remove it again
#   make info            show what was detected (paste this in bug reports)
#   make clean
#
# Build against another kernel:  make KDIR=/usr/src/linux-headers-6.12.9-amd64
# The upstream driver source is never modified: see src/compat.h and patches/.

KDIR ?= /lib/modules/$(shell uname -r)/build
KVER ?= $(shell uname -r)
BUILD ?= build
MODULE := arctic_fan_controller
SRC    := src/arctic_fan_controller.c
PATCH  := patches/0001-remove-prototype-macro.patch

# Immediate expansion: the kbuild sub-make changes directory, so capture the
# absolute repo path now rather than using $(CURDIR) inside a recipe.
THISDIR := $(shell pwd)

# --- where are the headers? Debian splits them into a -common directory -----
COMMON_INC  := $(firstword $(wildcard $(KDIR)/../linux-headers-*-common/include))
HDR_ROOTS   := $(KDIR)/include $(COMMON_INC)
find_hdr     = $(firstword $(foreach d,$(HDR_ROOTS),$(wildcard $(d)/$(1))))
HID_H        := $(call find_hdr,linux/hid.h)
DEVICE_H     := $(call find_hdr,linux/device.h)
UNALIGNED_H  := $(call find_hdr,linux/unaligned.h)

# --- probe the target kernel (bracket classes, not \( \): make's $(shell)
#     parser counts parentheses and an escaped paren breaks it) ---------------
HAVE_KZALLOC_OBJ := $(shell [ -n '$(DEVICE_H)' ] && grep -qs 'devm_kzalloc_obj' '$(DEVICE_H)' && echo y)
HID_REMOVE_VOID  := $(shell [ -n '$(HID_H)' ] && grep -Eq 'void[[:space:]]*[(][*]remove[)]' '$(HID_H)' && echo y)

ccflags-y := -I$(THISDIR)/src -include compat.h
ifeq ($(UNALIGNED_H),)
ccflags-y += -I$(THISDIR)/shim
endif
ifeq ($(HAVE_KZALLOC_OBJ),)
ccflags-y += -DARCTIC_NO_DEVM_KZALLOC_OBJ
endif
ifneq ($(HID_REMOVE_VOID),y)
ccflags-y += -DARCTIC_REMOVE_RETURNS_INT
endif

obj-m += $(MODULE).o

.PHONY: all modules dkms-build install uninstall clean info help

all: modules

# kbuild wants a Makefile in the M= directory, so generate one carrying our flags.
$(BUILD)/Makefile: Makefile src/compat.h shim/linux/unaligned.h
	@mkdir -p $(BUILD)
	@printf 'obj-m += $(MODULE).o\nccflags-y := $(ccflags-y)\n' > $@

$(BUILD)/$(MODULE).c: $(SRC) $(PATCH)
	@mkdir -p $(BUILD)
	@cp $(SRC) $@
	@patch -s -p1 -d $(BUILD) < $(PATCH)
	@echo "  PATCH   $(MODULE).c (->remove prototype routed through compat.h)"

modules: $(BUILD)/$(MODULE).c $(BUILD)/Makefile
	@test -d '$(KDIR)' || { echo "no kernel headers at $(KDIR); install linux-headers-$(KVER) or pass KDIR=..."; exit 1; }
	@test -n '$(HID_H)' || { echo "linux/hid.h not found under: $(HDR_ROOTS)"; exit 1; }
	@$(MAKE) -sC $(KDIR) M=$(THISDIR)/$(BUILD) modules

# DKMS builds in place and looks for the .ko at the top of its build tree.
dkms-build: modules
	@cp -f $(BUILD)/$(MODULE).ko .

info:
	@echo "kernel            : $(KVER)"
	@echo "kbuild dir        : $(KDIR)"
	@echo "header search     : $(HDR_ROOTS)"
	@echo "linux/hid.h       : $(or $(HID_H),NOT FOUND)  -> remove() is $(if $(HID_REMOVE_VOID),void,int)"
	@echo "linux/device.h    : $(or $(DEVICE_H),NOT FOUND)  -> devm_kzalloc_obj $(if $(HAVE_KZALLOC_OBJ),present,absent)"
	@echo "linux/unaligned.h : $(or $(UNALIGNED_H),absent - using shim/)"
	@echo "ccflags-y         : $(ccflags-y)"

install: modules
	@install -d /lib/modules/$(KVER)/extra
	install -m 0644 $(BUILD)/$(MODULE).ko /lib/modules/$(KVER)/extra/
	depmod -a $(KVER)
	@echo "installed. Load now with: sudo modprobe $(MODULE)"
	@echo "or just plug the controller in — udev loads it via its modalias."

uninstall:
	@rmmod $(MODULE) 2>/dev/null || true
	rm -f /lib/modules/$(KVER)/extra/$(MODULE).ko
	depmod -a $(KVER)
	@echo "removed for $(KVER). Installed via dkms instead? sudo dkms remove arctic-fan-controller/<ver> --all"

clean:
	@rm -rf $(BUILD)
	@echo "  CLEAN   build/"

help:
	@sed -n '2,12p' Makefile
