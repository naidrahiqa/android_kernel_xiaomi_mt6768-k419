/* SPDX-License-Identifier: GPL-2.0 */
#ifndef _LINUX_BOEFFLA_WL_BLOCKER_H
#define _LINUX_BOEFFLA_WL_BLOCKER_H

#ifdef CONFIG_BOEFFLA_WL_BLOCKER
bool boeffla_wl_blocker_is_blocked(const char *name);
#else
static inline bool boeffla_wl_blocker_is_blocked(const char *name)
{
	return false;
}
#endif

#endif /* _LINUX_BOEFFLA_WL_BLOCKER_H */
