#!/bin/sh
# verify.sh — check the driver, the device and the sysfs surface.
# Read-only except for one optional duty-cycle round trip (--spin).
set -eu

CHIP_NAME=arctic_fan
MOD=arctic_fan_controller

say() { printf '%s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*"; exit 1; }

say "== module =="
if grep -q "^${MOD} " /proc/modules 2>/dev/null; then
	say "loaded: $(grep "^${MOD} " /proc/modules)"
else
	warn="not loaded"
	if [ -f "/lib/modules/$(uname -r)/extra/${MOD}.ko" ] || modinfo "${MOD}" >/dev/null 2>&1; then
		say "${warn}, but installed -> sudo modprobe ${MOD}"
	else
		say "${warn} and not installed -> sudo make install"
	fi
fi

say
say "== usb device =="
if [ -r /sys/bus/usb/devices ]; then
	found=""
	for d in /sys/bus/usb/devices/*/idVendor; do
		[ -e "$d" ] || continue
		if [ "$(cat "$d")" = "3904" ]; then
			p=$(dirname "$d")
			found="$p $(cat "$p/idProduct")"
			say "attached: $found"
		fi
	done
	[ -n "$found" ] || say "no VID 0x3904 device on USB — is it plugged in, and is the SATA power lead connected?"
else
	say "skipped (no /sys/bus/usb)"
fi

say
say "== hwmon chip =="
chip=""
for h in /sys/class/hwmon/*; do
	[ -e "$h/name" ] || continue
	if [ "$(cat "$h/name" 2>/dev/null)" = "$CHIP_NAME" ]; then chip="$h"; fi
done
if [ -z "$chip" ]; then
	bad "hwmon chip '$CHIP_NAME' not present. Check 'dmesg | tail' and that the module loaded."
fi
say "chip dir: $chip (hwmon index $(basename "$chip"))"

say
say "== channels =="
i=1
while [ "$i" -le 10 ]; do
	rpm="$chip/fan${i}_input"; pwm="$chip/pwm${i}"
	if [ -e "$rpm" ] && [ -e "$pwm" ]; then
		printf 'ch%-2s rpm=%-6s duty=%s/255 (%s%%)\n' "$i" "$(cat "$rpm")" "$(cat "$pwm")" "$(( $(cat "$pwm") * 100 / 255 ))"
	else
		printf 'ch%-2s (no sysfs entries)\n' "$i"
	fi
	i=$((i + 1))
done

say
say "RPM values refresh at ~1 Hz; duty reads are the driver's cache, not the hardware."
case "${1:-}" in
	--spin)
		say "--spin: ramping every channel to 255 for 3 s, then back to what it was"
		old=$(for i in $(seq 1 10); do cat "$chip/pwm$i"; done | tr '\n' ' ')
		i=1; for v in $old; do echo 255 > "$chip/pwm$i"; i=$((i + 1)); done
		sleep 3
		i=1; for v in $old; do echo "$v" > "$chip/pwm$i"; i=$((i + 1)); done
		say "restored: $old"
		;;
esac
