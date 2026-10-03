/* SPDX-License-Identifier: GPL-2.0 */
#ifndef _LINUX_DYNAMIC_FSYNC_H
#define _LINUX_DYNAMIC_FSYNC_H

#ifdef CONFIG_DYNAMIC_FSYNC
extern bool dyn_fsync_active;
extern bool dyn_fsync_suspended;
#else
#define dyn_fsync_active false
#define dyn_fsync_suspended false
#endif

#endif /* _LINUX_DYNAMIC_FSYNC_H */
