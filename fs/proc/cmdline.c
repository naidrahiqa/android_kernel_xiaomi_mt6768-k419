// SPDX-License-Identifier: GPL-2.0
#include <linux/fs.h>
#include <linux/init.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>

#include <linux/string.h>

static int cmdline_proc_show(struct seq_file *m, void *v)
{
	const char *src = saved_command_line;
	const char *next;
	bool first = true;

	while (*src) {
		size_t len;

		while (*src == ' ')
			src++;
		if (!*src)
			break;

		next = strchrnul(src, ' ');
		len = (size_t)(next - src);

		if (!first)
			seq_putc(m, ' ');
		first = false;

		if (len == strlen("androidboot.selinux=permissive") &&
		    strncmp(src, "androidboot.selinux=permissive", len) == 0) {
			seq_puts(m, "androidboot.selinux=enforcing");
		} else if (len == strlen("androidboot.veritymode=disabled") &&
			   strncmp(src, "androidboot.veritymode=disabled", len) == 0) {
			seq_puts(m, "androidboot.veritymode=enforcing");
		} else if (len == strlen("androidboot.verifiedbootstate=orange") &&
			   strncmp(src, "androidboot.verifiedbootstate=orange", len) == 0) {
			seq_puts(m, "androidboot.verifiedbootstate=green");
		} else if (len == strlen("androidboot.vbmeta.device_state=unlocked") &&
			   strncmp(src, "androidboot.vbmeta.device_state=unlocked", len) == 0) {
			seq_puts(m, "androidboot.vbmeta.device_state=locked");
		} else {
			seq_write(m, src, len);
		}

		src = next;
	}
	seq_putc(m, '\n');
	return 0;
}

static int __init proc_cmdline_init(void)
{
	proc_create_single("cmdline", 0, NULL, cmdline_proc_show);
	return 0;
}
fs_initcall(proc_cmdline_init);
