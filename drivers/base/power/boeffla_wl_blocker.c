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
#include <linux/rcupdate.h>
#include <linux/mutex.h>
#include <linux/uaccess.h>
#include <linux/boeffla_wl_blocker.h>

#define BOEFFLA_WL_BLOCKER_VERSION "1.2.0"
#define MAX_BLOCKED_WLS 64
#define MAX_WL_NAME_LEN 64

struct boeffla_wl_table {
	struct rcu_head rcu;
	int count;
	char names[MAX_BLOCKED_WLS][MAX_WL_NAME_LEN];
};

static struct boeffla_wl_table __rcu *wl_table;
static DEFINE_MUTEX(wl_update_mutex);
static bool debug_log = false;

bool boeffla_wl_blocker_is_blocked(const char *name)
{
	struct boeffla_wl_table *tbl;
	bool blocked = false;
	int i;

	if (!name)
		return false;

	rcu_read_lock();
	tbl = rcu_dereference(wl_table);
	if (tbl) {
		for (i = 0; i < tbl->count; i++) {
			if (strcmp(name, tbl->names[i]) == 0) {
				blocked = true;
				break;
			}
		}
	}
	rcu_read_unlock();

	if (blocked && debug_log)
		pr_info("boeffla_wl_blocker: blocked wakelock '%s'\n", name);

	return blocked;
}
EXPORT_SYMBOL(boeffla_wl_blocker_is_blocked);

static ssize_t wakelock_blocker_show(struct device *dev,
				     struct device_attribute *attr,
				     char *buf)
{
	struct boeffla_wl_table *tbl;
	int i, len = 0;

	rcu_read_lock();
	tbl = rcu_dereference(wl_table);
	if (tbl) {
		for (i = 0; i < tbl->count; i++) {
			len += scnprintf(buf + len, PAGE_SIZE - len, "%s%s",
					 tbl->names[i],
					 (i < tbl->count - 1) ? ";" : "");
		}
	}
	rcu_read_unlock();

	len += scnprintf(buf + len, PAGE_SIZE - len, "\n");
	return len;
}

static ssize_t wakelock_blocker_store(struct device *dev,
				      struct device_attribute *attr,
				      const char *buf, size_t count)
{
	struct boeffla_wl_table *new_tbl, *old_tbl;
	char *tmp, *orig, *token;
	int count_new = 0;

	orig = kstrdup(buf, GFP_KERNEL);
	if (!orig)
		return -ENOMEM;

	new_tbl = kzalloc(sizeof(*new_tbl), GFP_KERNEL);
	if (!new_tbl) {
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
				strlcpy(new_tbl->names[count_new], token, MAX_WL_NAME_LEN);
				count_new++;
			} else {
				break;
			}
		}
	}

	new_tbl->count = count_new;
	kfree(orig);

	mutex_lock(&wl_update_mutex);
	old_tbl = rcu_dereference_protected(wl_table, lockdep_is_held(&wl_update_mutex));
	rcu_assign_pointer(wl_table, new_tbl);
	mutex_unlock(&wl_update_mutex);

	if (old_tbl)
		kfree_rcu(old_tbl, rcu);

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
	struct boeffla_wl_table *tbl;
	int ret, i;

	tbl = kzalloc(sizeof(*tbl), GFP_KERNEL);
	if (!tbl)
		return -ENOMEM;

	for (i = 0; i < ARRAY_SIZE(default_wls) && i < MAX_BLOCKED_WLS; i++) {
		strlcpy(tbl->names[i], default_wls[i], MAX_WL_NAME_LEN);
		tbl->count++;
	}
	RCU_INIT_POINTER(wl_table, tbl);

	ret = misc_register(&boeffla_wl_blocker_dev);
	if (ret) {
		pr_err("boeffla_wl_blocker: failed to register misc device\n");
		kfree(tbl);
		return ret;
	}

	pr_info("boeffla_wl_blocker: Generic Wakelock Blocker v%s initialized (%d default wls)\n",
		BOEFFLA_WL_BLOCKER_VERSION, tbl->count);
	return 0;
}
late_initcall(boeffla_wl_blocker_init);
