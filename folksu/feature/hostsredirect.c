// SPDX-License-Identifier: GPL-2.0-only
/*
 * Copyright (C) 2026 \xx (backslashxx)
 * Cherry-picked from xxKSU for FolkSU
 */

#include <linux/fs.h>
#include <linux/file.h>
#include <linux/namei.h>
#include <linux/cred.h>
#include <linux/uaccess.h>
#include <linux/sched.h>
#include <linux/fcntl.h>
#include "hostsredirect.h"
#include "klog.h"

bool ksu_hostsredirect_active __read_mostly = false;
extern const struct cred *ksu_cred;
extern bool ksu_module_mounted;
extern bool ksu_kernel_umount_enabled;

void ksu_hostsredirect_init(void)
{
    struct path kpath;
    if (kern_path("/data/adb/hosts", 0, &kpath)) {
        ksu_hostsredirect_active = false;
        return;
    }

    path_put(&kpath);
    ksu_hostsredirect_active = true;
    pr_info("ksu_hostsredirect: /data/adb/hosts found! Enabling hosts redirection\n");
}

void ksu_hosts_file_redirect(const char __user *filename, int flags, int *fd_ptr)
{
    if (!ksu_hostsredirect_active)
        return;

    if (unlikely(test_thread_flag(TIF_KSU_UNMOUNTABLE)))
        return;

    if (!ksu_module_mounted || !ksu_kernel_umount_enabled)
        return;

    if (!filename)
        return;

    static const char hf[] = "/system/etc/hosts";
    char buf[sizeof(hf)];

    if (strncpy_from_user(buf, filename, sizeof(buf)) != sizeof(hf) - 1)
        return;

    if (memcmp(buf, hf, sizeof(hf) - 1) != 0)
        return;

    const struct cred *saved = override_creds(ksu_cred);
    struct file *filp = filp_open("/data/adb/hosts", O_RDONLY, 0);
    revert_creds(saved);

    if (IS_ERR(filp))
        return;

    if (!is_compat_task() && force_o_largefile())
        flags |= O_LARGEFILE;

    int fd = get_unused_fd_flags(flags);
    if (fd < 0) {
        fput(filp);
        return;
    }

    fd_install(fd, filp);
    *fd_ptr = fd;
}
