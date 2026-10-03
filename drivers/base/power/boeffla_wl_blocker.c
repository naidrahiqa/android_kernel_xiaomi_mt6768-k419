// SPDX-License-Identifier: GPL-2.0
/*
 * Generic Wakelock Blocker Driver (Boeffla-style)
 *
 * Copyright (C) 2014-2015 AndiP (Lord Boeffla)
 * Adapted for Linux 4.19+ and Xiaomi MT6768
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/miscdevice.h>
#include <linux/fs.h>
#include <linux/string.h>
#include <linux/slab.h>
#include <linux/spinlock.h>
#include <linux/uaccess.h>
#include <linux/boeffla_wl_blocker.h>

#define BOEFFLA_WL_BLOCKER_VERSION "1.1.0"
#define MAX_BLOCKED_WLS 64
#define MAX_WL_NAME_LEN 64

static DEFINE_SPINLOCK(wl_lock);
static char blocked_wls[MAX_BLOCKED_WLS][MAX_WL_NAME_LEN];
static int num_blocked_wls = 0;
static bool debug_log = false;

bool boeffla_wl_blocker_is_blocked(const char *name)
{
	unsigned long flags;
	int i;
	bool blocked = false;

	if (!name || num_blocked_wls == 0)
		return false;

	spin_lock_irqsave(&wl_lock, flags);
	for (i = 0; i < num_blocked_wls; i++) {
		if (strcmp(name, blocked_wls[i]) == 0) {
			blocked = true;
			break;
		}
	}
	spin_unlock_irqrestore(&wl_lock, flags);

	if (blocked && debug_log)
		pr_info("boeffla_wl_blocker: blocked wakelock '%s'\n", name);

	return blocked;
}
EXPORT_SYMBOL(boeffla_wl_blocker_is_blocked);

static ssize_t wakelock_blocker_show(struct device *dev,
				     struct device_attribute *attr,
				     char *buf)
{
	unsigned long flags;
	int i, len = 0;

	spin_lock_irqsave(&wl_lock, flags);
	for (i = 0; i < num_blocked_wls; i++) {
		len += scnprintf(buf + len, PAGE_SIZE - len, "%s%s",
				 blocked_wls[i],
				 (i < num_blocked_wls - 1) ? ";" : "");
	}
	spin_unlock_irqrestore(&wl_lock, flags);

	len += scnprintf(buf + len, PAGE_SIZE - len, "\n");
	return len;
}

static ssize_t wakelock_blocker_store(struct device *dev,
				      struct device_attribute *attr,
				      const char *buf, size_t count)
{
	char *tmp, *orig, *token;
	unsigned long flags;
	int count_new = 0;
	typedef char wl_name_t[MAX_WL_NAME_LEN];
	wl_name_t *new_wls;

	orig = kstrdup(buf, GFP_KERNEL);
	if (!orig)
		return -ENOMEM;

	new_wls = kzalloc(sizeof(wl_name_t) * MAX_BLOCKED_WLS, GFP_KERNEL);
	if (!new_wls) {
		kfree(orig);
		return -ENOMEM;
	}

	tmp = strim(orig);

	if (strlen(tmp) > 0) {
		while ((token = strsep(&tmp, ";")) != NULL) {
			token = strim(token);
			if (strlen(token) == 0)
				continue;

			if (count_new < MAX_BLOCKED_WLS) {
				strlcpy(new_wls[count_new], token, MAX_WL_NAME_LEN);
				count_new++;
			} else {
				break;
			}
		}
	}

	kfree(orig);

	spin_lock_irqsave(&wl_lock, flags);
	num_blocked_wls = count_new;
	memcpy(blocked_wls, new_wls, sizeof(wl_name_t) * MAX_BLOCKED_WLS);
	spin_unlock_irqrestore(&wl_lock, flags);

	kfree(new_wls);

	pr_info("boeffla_wl_blocker: updated blocker list (%d items)\n", count_new);
	return count;
}

static ssize_t debug_show(struct device *dev,
			  struct device_attribute *attr,
			  char *buf)
{
	return sprintf(buf, "%d\n", debug_log ? 1 : 0);
}

static ssize_t debug_store(struct device *dev,
			   struct device_attribute *attr,
			   const char *buf, size_t count)
{
	unsigned int val;

	if (kstrtouint(buf, 0, &val) < 0)
		return -EINVAL;

	debug_log = (val != 0);
	return count;
}

static ssize_t version_show(struct device *dev,
			    struct device_attribute *attr,
			    char *buf)
{
	return sprintf(buf, "%s\n", BOEFFLA_WL_BLOCKER_VERSION);
}

static DEVICE_ATTR_RW(wakelock_blocker);
static DEVICE_ATTR_RW(debug);
static DEVICE_ATTR_RO(version);

static struct attribute *boeffla_wl_blocker_attrs[] = {
	&dev_attr_wakelock_blocker.attr,
	&dev_attr_debug.attr,
	&dev_attr_version.attr,
	NULL,
};

static const struct attribute_group boeffla_wl_blocker_group = {
	.attrs = boeffla_wl_blocker_attrs,
};

static const struct attribute_group *boeffla_wl_blocker_groups[] = {
	&boeffla_wl_blocker_group,
	NULL,
};

static struct miscdevice boeffla_wl_blocker_dev = {
	.minor = MISC_DYNAMIC_MINOR,
	.name = "boeffla_wakelock_blocker",
	.groups = boeffla_wl_blocker_groups,
};

static const char *default_wls[] = {
	"wlan_ipa",
	"wlan_pno_wl",
	"NETLINK",
};

static int __init boeffla_wl_blocker_init(void)
{
	int ret, i;

	for (i = 0; i < ARRAY_SIZE(default_wls) && i < MAX_BLOCKED_WLS; i++) {
		strlcpy(blocked_wls[i], default_wls[i], MAX_WL_NAME_LEN);
		num_blocked_wls++;
	}

	ret = misc_register(&boeffla_wl_blocker_dev);
	if (ret) {
		pr_err("boeffla_wl_blocker: failed to register misc device\n");
		return ret;
	}

	pr_info("boeffla_wl_blocker: Generic Wakelock Blocker v%s initialized (%d default wls)\n",
		BOEFFLA_WL_BLOCKER_VERSION, num_blocked_wls);
	return 0;
}
late_initcall(boeffla_wl_blocker_init);
