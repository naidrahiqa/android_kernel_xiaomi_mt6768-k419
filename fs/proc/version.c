// SPDX-License-Identifier: GPL-2.0
#include <linux/fs.h>
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include <linux/utsname.h>
#include <linux/cred.h>
#include <linux/capability.h>
#include <linux/string.h>

static int version_proc_show(struct seq_file *m, void *v)
{
	kuid_t uid = current_uid();
	const char *release = utsname()->release;
	char clean_release[65];
	int i, j = 0;

	if (!uid_eq(uid, GLOBAL_ROOT_UID) && uid.val >= 10000 &&
	    !capable(CAP_SYS_ADMIN)) {
		/* Strip non-ASCII bytes (e.g. emoji) */
		for (i = 0; release[i] && j < sizeof(clean_release) - 1; i++) {
			unsigned char c = (unsigned char)release[i];
			if (c >= 0x80)
				continue;
			clean_release[j++] = c;
		}
		clean_release[j] = '\0';

		/* Replace custom branding keyword if present */
		if (strstr(clean_release, "PawwwNunungggg")) {
			char *p = strstr(clean_release, "PawwwNunungggg");
			memcpy(p, "android", 7);
			memmove(p + 7, p + 14, strlen(p + 14) + 1);
		}
		release = clean_release;
	}

	seq_printf(m, linux_proc_banner,
		utsname()->sysname,
		release,
		utsname()->version);
	return 0;
}

static int __init proc_version_init(void)
{
	proc_create_single("version", 0, NULL, version_proc_show);
	return 0;
}
fs_initcall(proc_version_init);
