/* SPDX-License-Identifier: GPL-2.0 OR BSD-3-Clause */
/*
 * compat.h — make the mainline ARCTIC Fan Controller driver build on kernels
 * that predate its v7.2 merge. Force-included by the Makefile (-include), so
 * drivers/hwmon/arctic_fan_controller.c stays byte-for-byte upstream.
 *
 * Everything here is keyed off what the *target kernel actually provides*
 * (the Makefile probes its headers and passes -D flags), never off a guessed
 * version number — distribution kernels backport these APIs out of order.
 */

#ifndef ARCTIC_COMPAT_H
#define ARCTIC_COMPAT_H

#include <linux/version.h>
#include <linux/device.h>
#include <linux/slab.h>

/* ------------------------------------------------------------------------- */
/* hid_driver::remove return type                                            */
/*                                                                           */
/* Upstream changed ->remove() from int to void in v6.4, but e.g. Debian's    */
/* 6.1 already carries the void form while Ubuntu 22.04 (5.15) still wants    */
/* int. The Makefile greps include/linux/hid.h and defines                    */
/* ARCTIC_REMOVE_RETURNS_INT when the kernel still expects int.               */
/* ------------------------------------------------------------------------- */
#ifdef ARCTIC_REMOVE_RETURNS_INT
#define ARCTIC_REMOVE_PROTO(name)	static int name
#define ARCTIC_REMOVE_RETURN		return 0;
#else
#define ARCTIC_REMOVE_PROTO(name)	static void name
#define ARCTIC_REMOVE_RETURN
#endif

/* ------------------------------------------------------------------------- */
/* devm_kzalloc_obj() — sized alloc helper added in later kernels.           */
/* Upstream call site is devm_kzalloc_obj(dev, *priv), which the classic      */
/* form spells with sizeof().                                                */
/* ------------------------------------------------------------------------- */
#ifdef ARCTIC_NO_DEVM_KZALLOC_OBJ
#define devm_kzalloc_obj(dev, type)	devm_kzalloc((dev), sizeof(type), GFP_KERNEL)
#endif

/* ------------------------------------------------------------------------- */
/* Struct-member group annotations (__dma_from_device_group_begin/end()).    */
/* Added in later kernels and used *inside* a struct definition, so on older */
/* kernels they must expand to something that keeps `NAME();` valid there:   */
/* two dummy char members. Cost: 2 bytes of padding per annotated group.     */
/* ------------------------------------------------------------------------- */
#ifndef __dma_from_device_group_begin
#define __dma_from_device_group_begin()	char __arctic_compat_pad_a
#endif
#ifndef __dma_from_device_group_end
#define __dma_from_device_group_end()	char __arctic_compat_pad_b
#endif

/* <linux/unaligned.h> moved in ~v6.7; when absent the Makefile adds shim/ to
 * the include path so the upstream #include resolves to <asm/unaligned.h>. */

#endif /* ARCTIC_COMPAT_H */
