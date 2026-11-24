#!/bin/sh
# refresh-upstream.sh — pull the current mainline driver and tell you whether
# this repo still applies cleanly. Never edits src/ unless you pass --write.
set -eu

URL="${1:-https://raw.githubusercontent.com/torvalds/linux/master/drivers/hwmon/arctic_fan_controller.c}"
SRC=src/arctic_fan_controller.c
PATCH=patches/0001-remove-prototype-macro.patch
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

command -v curl >/dev/null || { echo "curl required"; exit 1; }
curl -fsSL -o "$TMP" "$URL" || { echo "fetch failed: $URL"; exit 1; }

echo "upstream bytes : $(wc -c < "$TMP")  sha256 $(sha256sum "$TMP" | cut -d' ' -f1)"
echo "vendored bytes : $(wc -c < "$SRC")  sha256 $(sha256sum "$SRC" | cut -d' ' -f1)"

if cmp -s "$TMP" "$SRC"; then
	echo "identical — nothing to do."
	exit 0
fi

echo "differs. patch test against the new file:"
mkdir -p /tmp/arctic-refresh && cp "$TMP" /tmp/arctic-refresh/arctic_fan_controller.c
if patch -s --dry-run -p1 -d /tmp/arctic-refresh < "$PATCH"; then
	echo "  patches/0001 still applies cleanly."
	if [ "${1:-}" = "--write" ] || [ "${2:-}" = "--write" ]; then
		cp "$TMP" "$SRC"
		echo "  src/arctic_fan_controller.c updated. Now: make clean && make"
	else
		echo "  re-run with --write to adopt it (or pass a URL/tag as \$1)."
	fi
else
	echo "  PATCH NO LONGER APPLIES — upstream moved ->remove(). Re-create patches/0001"
	echo "  against the new file; see README ('Refreshing from upstream')."
fi
rm -rf /tmp/arctic-refresh
