#!/bin/sh
# dkms-setup.sh — stage, build and install this driver through DKMS so it
# rebuilds automatically on every kernel package install.
#
#   sudo scripts/dkms-setup.sh              # add + build + install
#   sudo scripts/dkms-setup.sh --dry-run    # print what would happen
#   scripts/dkms-setup.sh --help
#
# Re-running is safe: the existing DKMS registration is removed first, so this
# doubles as the "I edited the source / bumped PACKAGE_VERSION" updater.
#
# Test hooks (never needed on a real machine): DKMS_SOURCE_TREE, DKMS_TREE and
# DKMS_INSTALL_TREE redirect DKMS's three trees so the whole flow can run
# unprivileged in a scratch directory.
set -eu

PROG=${0##*/}
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

say()  { printf '%s\n' "$*"; }
warn() { printf 'WARN %s\n' "$*" >&2; }
die()  { printf 'ERROR %s\n' "$*" >&2; exit 1; }
run()  { say "  + $*"; [ "$DRY" = 1 ] || "$@"; }

usage() {
	sed -n '2,14p' "$0" | sed 's/^#\{1,2\} \{0,1\}//'
}

# --- args -------------------------------------------------------------------
DRY=0; FORCE=0
for a in "$@"; do
	case "$a" in
		-h|--help)     usage; exit 0 ;;
		-n|--dry-run)  DRY=1 ;;
		-f|--force)    FORCE=1 ;;
		*)             die "unknown option: $a (try --help)" ;;
	esac
done

# --- read the package identity out of dkms.conf -----------------------------
[ -f "$REPO/dkms.conf" ] || die "dkms.conf not found next to $REPO/scripts"
PKG=$(sed -n 's/^[[:space:]]*PACKAGE_NAME[[:space:]]*=[[:space:]]*"\{0,1\}\([^"]*\)"*/\1/p' "$REPO/dkms.conf")
VER=$(sed -n 's/^[[:space:]]*PACKAGE_VERSION[[:space:]]*=[[:space:]]*"\{0,1\}\([^"]*\)"*/\1/p' "$REPO/dkms.conf")
MOD=$(sed -n 's/^[[:space:]]*BUILT_MODULE_NAME\[0\][[:space:]]*=[[:space:]]*"\{0,1\}\([^"]*\)"*/\1/p' "$REPO/dkms.conf")
[ -n "$PKG" ] && [ -n "$VER" ] && [ -n "$MOD" ] \
	|| die "could not parse PACKAGE_NAME/PACKAGE_VERSION/BUILT_MODULE_NAME from dkms.conf"

KVER=$(uname -r)
SRC_DIR=${DKMS_SOURCE_TREE:-/usr/src}/$PKG-$VER

say "== $PROG: $PKG/$VER for kernel $KVER =="
say "repo     : $REPO"
say "stage dir: $SRC_DIR"

# --- is this even necessary? -----------------------------------------------
# The driver is mainline from Linux 7.2; on such a kernel it ships with the
# distro and a DKMS copy would only shadow it (and could regress).
KMAJ=$(printf '%s' "$KVER" | cut -d. -f1)
KMIN=$(printf '%s' "$KVER" | cut -d. -f2 | tr -dc '0-9')
if [ -n "$KMAJ" ] && [ "$KMAJ" -gt 7 ] 2>/dev/null || \
   { [ "${KMAJ:-0}" -eq 7 ] && [ "${KMIN:-0}" -ge 2 ] 2>/dev/null; }; then
	if [ "$FORCE" = 1 ]; then
		warn "kernel $KVER already has $MOD in-tree; proceeding anyway (--force)"
	else
		die "kernel $KVER is 7.2 or newer: '$MOD' is already in-tree and ships with your kernel. Nothing to build here. (Use --force to override.)"
	fi
fi

# --- dependencies -----------------------------------------------------------
# dkms, depmod and friends live in sbin, which a non-login shell may not carry.
# Add it before declaring anything missing.
for d in /usr/sbin /sbin; do
	case ":$PATH:" in *":$d:"*) ;; *) PATH="$PATH:$d" ;; esac
done
export PATH
for t in dkms make gcc patch depmod; do
	command -v "$t" >/dev/null 2>&1 || die "'$t' is required but not on PATH (apt install dkms build-essential patch kmod)"
done
[ -d "/lib/modules/$KVER/build" ] \
	|| die "no kernel headers at /lib/modules/$KVER/build — apt install linux-headers-$KVER"

# Show the auto-detection result; it is what makes this repo portable.
if [ -f "$REPO/Makefile" ]; then
	say
	say "== kernel feature detection =="
	( cd "$REPO" && make info ) 2>&1 | sed 's/^/  /'
fi

# --- root check (after all the read-only diagnostics) -----------------------
if [ "$(id -u)" != 0 ] && [ "$DRY" = 0 ] && [ -z "${DKMS_TREE:-}" ]; then
	say
	say "This needs root. Run:"
	say "    sudo $0"
	exit 1
fi

# --- DKMS tree redirection (test hooks) ------------------------------------
DKOPT=""
[ -n "${DKMS_SOURCE_TREE:-}" ]   && DKOPT="$DKOPT --sourcetree $DKMS_SOURCE_TREE"
[ -n "${DKMS_TREE:-}" ]          && DKOPT="$DKOPT --dkmstree $DKMS_TREE"
[ -n "${DKMS_INSTALL_TREE:-}" ]  && DKOPT="$DKOPT --installtree $DKMS_INSTALL_TREE"

# shellcheck disable=SC2086 # deliberate word splitting of the option list
dkms_() { run dkms $DKOPT "$@"; }
# Query helper: always executes (never a no-op under --dry-run) and honours the
# same tree redirections as the mutating commands above.
dkms_q() { dkms $DKOPT "$@" 2>/dev/null; }

# --- stage the source -------------------------------------------------------
# A clean mirror, not an overlay: stale files from a previous version must not
# survive into the next build. .git and build/ are never part of the package.
say
say "== stage source =="
if [ "$DRY" = 1 ]; then
	say "  + mirror $REPO -> $SRC_DIR (excluding .git/, build/)"
else
	mkdir -p "$SRC_DIR"
	if command -v rsync >/dev/null 2>&1; then
		rsync -a --delete --exclude '.git' --exclude 'build/' \
			--exclude '*.o' --exclude '*.ko' --exclude '*.mod' \
			"$REPO/" "$SRC_DIR/"
	else
		# no rsync: rebuild the directory from scratch instead of overlaying
		find "$SRC_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
		for item in src patches shim scripts Makefile dkms.conf; do
			[ -e "$REPO/$item" ] || die "expected $REPO/$item to exist"
			cp -a "$REPO/$item" "$SRC_DIR/"
		done
	fi
	say "  staged: $(find "$SRC_DIR" -type f | wc -l) files"
fi

# --- replace any previous registration -------------------------------------
say
say "== DKMS =="
if [ -n "$(dkms_q status | grep "^$PKG/$VER," || true)" ]; then
	say "existing registration found -> removing it first"
	# --all covers every kernel it was built for; ignore "not added" style errors.
	dkms_ remove "$PKG/$VER" --all || true
elif [ -n "$(dkms_q status | grep "^$PKG/" || true)" ]; then
	warn "another version of $PKG is registered: $(dkms_q status | grep "^$PKG/")"
fi

dkms_ add "$PKG/$VER"
dkms_ build "$PKG/$VER" -k "$KVER"
dkms_ install "$PKG/$VER" -k "$KVER"

# --- report ----------------------------------------------------------------
say
say "== result =="
dkms_q status | grep "^$PKG/" | sed 's/^/  /' || say "  (dkms status produced no output)"

say
if [ "$DRY" = 1 ]; then
	say "dry run — nothing was changed."
else
	say "Done. The module rebuilds and reinstalls on every future kernel package install."
	say "Load it now with:   sudo modprobe $MOD"
	say "Then check with:    scripts/verify.sh"
fi
say
say "Kernel is 7.2+ later? Then the driver is in-tree; remove this with:"
say "    sudo dkms remove $PKG/$VER --all"
