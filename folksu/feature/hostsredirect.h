/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Copyright (C) 2026 \xx (backslashxx)
 * Cherry-picked from xxKSU for FolkSU
 */

#ifndef __KSU_H_HOSTSREDIRECT
#define __KSU_H_HOSTSREDIRECT

#include <linux/fs.h>
#include <linux/file.h>
#include <linux/namei.h>
#include <linux/cred.h>
#include <linux/uaccess.h>
#include <linux/sched.h>

#ifndef TIF_KSU_UNMOUNTABLE
#define TIF_KSU_UNMOUNTABLE 30
#endif

extern bool ksu_hostsredirect_active;

void ksu_hostsredirect_init(void);
void ksu_hosts_file_redirect(const char __user *filename, int flags, int *fd_ptr);

#endif /* __KSU_H_HOSTSREDIRECT */
