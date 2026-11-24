/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Shim for kernels that have no <linux/unaligned.h> (it moved out of asm/ in
 * ~v6.7). The Makefile only puts shim/ on the include path when the target
 * kernel lacks the real header, so this can never shadow it on newer kernels.
 */
#ifndef _ARCTIC_SHIM_LINUX_UNALIGNED_H
#define _ARCTIC_SHIM_LINUX_UNALIGNED_H
#include <asm/unaligned.h>
#endif
