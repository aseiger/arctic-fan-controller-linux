# arctic-fan-controller-linux

Build and install the mainline **ARCTIC Fan Controller** hwmon driver on kernels
that predate its v7.2 merge — Debian 12/13, Ubuntu 22.04/24.04, and anything else
currently shipping an older kernel.

The device is a USB fan hub (**VID `0x3904`, PID `0xF001`**) with **10 independent
PWM channels and 10 tach inputs**. ARCTIC wrote the Linux driver themselves and
upstreamed it, so it is mainline from **Linux 7.2** — and there is no vendor repo,
which is why it is hard to find. This repo vendors that one upstream file
unmodified and adds a compatibility layer for older kernels.

```
fan[1-10]_input   RPM, pushed by the device at ~1 Hz (read-only)
pwm[1-10]         duty 0-255 (write sends an OUT report; read returns the cache)
hwmon chip name   arctic_fan
```

## Requirements

- kernel headers for the kernel you build against (`linux-headers-$(uname -r)` on Debian/Ubuntu)
- `build-essential`, `patch`, `kmod`
- Secure Boot: an unsigned module loads only if Secure Boot is off, or you sign it.
  Check with `mokutil --sb-state`.

## Quickstart

```sh
git clone <this-repo> && cd arctic-fan-controller-linux
make info          # what does this kernel already provide?
make               # patch a build copy + compile
sudo make install  # /lib/modules/$(uname -r)/extra + depmod
sudo modprobe arctic_fan_controller
scripts/verify.sh  # module, USB presence, hwmon chip, all 10 channels
```

`make info` prints the auto-detection result — include it in bug reports:

```
kernel          : 6.1.0-53-amd64
linux/unaligned.h present : no  -> -Ishim
devm_kzalloc_obj present  : no  -> -DARCTIC_NO_DEVM_KZALLOC_OBJ
hid_driver::remove        : void
```

Build against a specific kernel instead of the running one:

```sh
make KDIR=/usr/src/linux-headers-6.12.9-amd64
```

## Stay current across kernel updates (recommended)

Plain `make install` pins the module to one kernel. With DKMS it rebuilds on every
kernel package install:

```sh
sudo apt install dkms
sudo mkdir -p /usr/src/arctic-fan-controller-1.0
sudo cp -r src patches shim scripts Makefile dkms.conf /usr/src/arctic-fan-controller-1.0/
sudo dkms install arctic-fan-controller/1.0
```

Once your kernel is 7.2 or newer the driver is in-tree; then
`sudo dkms remove arctic-fan-controller/1.0 --all` and forget about it.

## How compatibility is handled (and why not version numbers)

The Makefile **greps the target kernel's own headers** and passes only the flags
that kernel needs:

| Gap on older kernels | Detection | Fix |
|---|---|---|
| `hid_driver::remove` returns `int` (upstream < 6.4, e.g. Ubuntu 22.04 / 5.15) | grep `include/linux/hid.h` | `-DARCTIC_REMOVE_RETURNS_INT` → `src/compat.h` supplies `ARCTIC_REMOVE_PROTO`/`ARCTIC_REMOVE_RETURN` via `patches/0001` |
| no `<linux/unaligned.h>` (moved out of `asm/` ~6.7) | file existence | `shim/linux/unaligned.h` on the include path, only when absent |
| no `devm_kzalloc_obj()` | grep `include/linux/device.h` | `-DARCTIC_NO_DEVM_KZALLOC_OBJ` → macro to `devm_kzalloc(dev, sizeof(type), GFP_KERNEL)` |
| no `__dma_from_device_group_begin()/end()` struct annotations | `#ifndef` in `compat.h` | expand to two dummy `char` members so `NAME();` stays valid inside a struct |

This matters because distros backport out of order: **Debian's 6.1 already uses the
void `->remove()`** that upstream added in 6.4, so a `LINUX_VERSION_IS_LESS(6,4,0)`
test would generate the wrong prototype and fail to compile.

`src/arctic_fan_controller.c` is never modified — see [UPSTREAM.md](UPSTREAM.md).

## Status

| Kernel | Result |
|---|---|
| Debian 12 `6.1.0-53-amd64` | **built clean, zero warnings** (verified on a real X399 box; Secure Boot off) |
| Anything else 5.10+ | should build — detection is per-kernel, but untested here. Send `make info` output + the compiler error if it doesn't |
| 7.2+ | don't use this repo; the driver ships in your kernel |

Not verified by loading against real hardware: this repo was validated by
compilation and by reading the driver + kernel docs, not by driving a controller.

## Uninstall

```sh
sudo make uninstall                     # if installed with `make install`
sudo dkms remove arctic-fan-controller/1.0 --all   # if installed with dkms
```

## What you should know before putting fans on this hub

- **Manual-only.** The device never adjusts PWM itself and has no fallback curve.
  If nothing commands it, it sits at the MCU factory default of **40 %** — including
  right after power-on and after resume from suspend (the driver resets its cache to
  40 % on resume, and if the device kept power you must re-apply your duty cycles).
- **`pwm*` reads are a host cache**, not hardware state: the device has no
  `GET_REPORT`. Command every channel you rely on instead of trusting a read.
- The driver updates `pwm*` only after the device ACKs the command, and each OUT
  report carries all 10 channels.
- Needs SATA power from the PSU plus a motherboard USB 2.0 header; hot-plug works.
- If these fans are keeping silicon alive, leave one fan on a BIOS-controlled header
  as dumb insurance against the daemon dying or USB dropping out.

## Layout

```
src/arctic_fan_controller.c   upstream driver, unmodified (see UPSTREAM.md)
src/compat.h                  compat macros, force-included by the Makefile
shim/linux/unaligned.h        used only when the kernel lacks the real header
patches/0001-*.patch          2 hunks: ->remove() prototype + return
Makefile                      probing, build, install, uninstall, info
dkms.conf                     DKMS packaging
scripts/verify.sh             post-install checks (--spin does a duty round trip)
scripts/refresh-upstream.sh   pull newer upstream, check the patch still applies
```

Licence: the driver is dual BSD/GPL as shipped by its author; the compat layer in
this repo is offered under the same terms.
