# Upstream provenance

| | |
|---|---|
| Driver | `arctic_fan_controller` — hwmon driver for the ARCTIC Fan Controller (USB Custom HID, VID `0x3904`, PID `0xF001`, 10 channels) |
| Author | Aureo Serrano de Souza `<aureo.serrano@arctic.de>` (ARCTIC wrote it and submitted it upstream) |
| Upstream path | `drivers/hwmon/arctic_fan_controller.c` in `torvalds/linux` |
| First release containing it | **Linux 7.2** (merged via tag `hwmon-for-v7.2`, commit `fc2ce3ee106f2d53eb344f5c4963c897bbb21634`) |
| Vendored copy | `src/arctic_fan_controller.c`, fetched from `master` on 2026-11-24 |
| sha256 | `dd3b39944995c57c7c43eb9661bf1f0dac9a81327fbdae9208585eb3ab38d723` |
| Licence | Dual BSD/GPL, per the module's `MODULE_LICENSE` — see the header of the source file |
| Kernel docs | `Documentation/hwmon/arctic_fan_controller.rst` → https://www.kernel.org/doc/html/latest/hwmon/arctic_fan_controller.html |

**`src/arctic_fan_controller.c` is upstream, unmodified.** Every compatibility
change lives outside it:

- `src/compat.h` — force-included with `-include`; provides the missing macros.
- `shim/linux/unaligned.h` — only on the include path when the kernel has no real `<linux/unaligned.h>`.
- `patches/0001-remove-prototype-macro.patch` — two hunks that route the `->remove()`
  prototype and its return through `ARCTIC_REMOVE_PROTO` / `ARCTIC_REMOVE_RETURN`.

## Refreshing from upstream

```sh
scripts/refresh-upstream.sh              # fetch master, test the patch, change nothing
scripts/refresh-upstream.sh --write      # adopt it if the patch still applies
scripts/refresh-upstream.sh https://raw.githubusercontent.com/torvalds/linux/v7.2/drivers/hwmon/arctic_fan_controller.c --write
```

If the script reports that `patches/0001` no longer applies, upstream almost
certainly reworked `->remove()` again. Re-create it in two steps:

1. Copy the new file over `src/arctic_fan_controller.c`.
2. Change the `->remove()` definition to
   `ARCTIC_REMOVE_PROTO(arctic_fan_remove)(struct hid_device *hdev)` and add a
   line `ARCTIC_REMOVE_RETURN` as the last statement, then
   `diff -u` against a pristine copy into `patches/0001-remove-prototype-macro.patch`
   with `--- a/arctic_fan_controller.c` / `+++ b/arctic_fan_controller.c` headers.

Then `make clean && make info && make`.

## Why not just patch the file?

Because distro kernels backport these APIs out of order — Debian's 6.1 already
has the **void** `hid_driver::remove` that upstream introduced in 6.4, while
Ubuntu 22.04's 5.15 still wants `int`. Version-number tests get that wrong, so the
Makefile greps the target kernel's own headers instead. Keeping upstream pristine
means a refresh is one file copy plus a patch-application check.
