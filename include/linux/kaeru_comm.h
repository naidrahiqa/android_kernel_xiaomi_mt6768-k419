/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Kaeru Communication Module - Header
 *
 * Exported functions for kernel modules to query Kaeru LK state.
 */

#ifndef _LINUX_KAERU_COMM_H
#define _LINUX_KAERU_COMM_H

#include <linux/types.h>

/* Kaeru magic and version */
#define KAERU_MAGIC     0x4B414552  /* "KAER" */
#define KAERU_VERSION   0x00020000  /* v2.0.0 */

/* Kaeru flags (written to DRAM by LK) */
#define KAERU_FLAG_OVERCLOCK    (1 << 0)
#define KAERU_FLAG_SPOOF_LOCK   (1 << 1)
#define KAERU_FLAG_RECOVERY     (1 << 2)
#define KAERU_FLAG_DOWNLOAD     (1 << 3)

#ifdef CONFIG_KAERU_COMM

bool kaeru_is_active(void);
bool kaeru_is_overclock(void);
bool kaeru_is_spoofing(void);
bool kaeru_is_recovery(void);
bool kaeru_is_download(void);

#else

static inline bool kaeru_is_active(void)   { return false; }
static inline bool kaeru_is_overclock(void) { return false; }
static inline bool kaeru_is_spoofing(void)  { return false; }
static inline bool kaeru_is_recovery(void)  { return false; }
static inline bool kaeru_is_download(void)  { return false; }

#endif /* CONFIG_KAERU_COMM */

#endif /* _LINUX_KAERU_COMM_H */
