// SPDX-License-Identifier: GPL-2.0
/*
 * Dynamic Fsync
 *
 * Copyright (C) 2013 Aaron Segaert <asegaert@gmail.com>
 * Adapted for Linux 4.19+ and Xiaomi MT6768
 */

#include <linux/module.h>
#include <linux/kobject.h>
#include <linux/sysfs.h>
#include <linux/init.h>
#include <linux/fs.h>
#include <linux/syscalls.h>
#include <linux/workqueue.h>
#include <linux/fb.h>
#include <linux/notifier.h>
#include <linux/dynamic_fsync.h>

#define DYN_FSYNC_VERSION "2.0"

bool dyn_fsync_active = true;
EXPORT_SYMBOL(dyn_fsync_active);

bool dyn_fsync_suspended = false;
EXPORT_SYMBOL(dyn_fsync_suspended);

static struct workqueue_struct *dyn_fsync_wq;
static struct work_struct dyn_fsync_work;

static void dyn_fsync_work_fn(struct work_struct *work)
{
	ksys_sync();
}

static int dyn_fsync_notifier_callback(struct notifier_block *this,
				       unsigned long event, void *data)
{
	struct fb_event *evdata = data;
	int *blank;

	if (event != FB_EVENT_BLANK)
		return 0;

	if (!evdata || !evdata->data)
		return 0;

	blank = evdata->data;

	switch (*blank) {
	case FB_BLANK_UNBLANK:
		dyn_fsync_suspended = false;
		break;
	case FB_BLANK_POWERDOWN:
	case FB_BLANK_HSYNC_SUSPEND:
	case FB_BLANK_VSYNC_SUSPEND:
	case FB_BLANK_NORMAL:
		dyn_fsync_suspended = true;
		if (dyn_fsync_active && dyn_fsync_wq)
			queue_work(dyn_fsync_wq, &dyn_fsync_work);
		break;
	}

	return 0;
}

static struct notifier_block dyn_fsync_notifier = {
	.notifier_call = dyn_fsync_notifier_callback,
};

static ssize_t dyn_fsync_active_show(struct kobject *kobj,
				     struct kobj_attribute *attr,
				     char *buf)
{
	return sprintf(buf, "%u\n", dyn_fsync_active ? 1 : 0);
}

static ssize_t dyn_fsync_active_store(struct kobject *kobj,
				      struct kobj_attribute *attr,
				      const char *buf, size_t count)
{
	unsigned int val;

	if (kstrtouint(buf, 0, &val) < 0)
		return -EINVAL;

	if (val > 1)
		return -EINVAL;

	if (dyn_fsync_active && !val) {
		dyn_fsync_active = false;
		ksys_sync();
	} else {
		dyn_fsync_active = (val != 0);
	}

	return count;
}

static ssize_t dyn_fsync_suspended_show(struct kobject *kobj,
					struct kobj_attribute *attr,
					char *buf)
{
	return sprintf(buf, "%u\n", dyn_fsync_suspended ? 1 : 0);
}

static ssize_t dyn_fsync_version_show(struct kobject *kobj,
				      struct kobj_attribute *attr,
				      char *buf)
{
	return sprintf(buf, "%s\n", DYN_FSYNC_VERSION);
}

static struct kobj_attribute dyn_fsync_active_attr =
	__ATTR(Dyn_fsync_active, 0644, dyn_fsync_active_show, dyn_fsync_active_store);

static struct kobj_attribute dyn_fsync_active_attr_lower =
	__ATTR(dyn_fsync_active, 0644, dyn_fsync_active_show, dyn_fsync_active_store);

static struct kobj_attribute dyn_fsync_suspended_attr =
	__ATTR(Dyn_fsync_suspended, 0444, dyn_fsync_suspended_show, NULL);

static struct kobj_attribute dyn_fsync_suspended_attr_lower =
	__ATTR(dyn_fsync_suspended, 0444, dyn_fsync_suspended_show, NULL);

static struct kobj_attribute dyn_fsync_version_attr =
	__ATTR(Dyn_fsync_version, 0444, dyn_fsync_version_show, NULL);

static struct kobj_attribute dyn_fsync_version_attr_lower =
	__ATTR(dyn_fsync_version, 0444, dyn_fsync_version_show, NULL);

static struct attribute *dyn_fsync_attrs[] = {
	&dyn_fsync_active_attr.attr,
	&dyn_fsync_active_attr_lower.attr,
	&dyn_fsync_suspended_attr.attr,
	&dyn_fsync_suspended_attr_lower.attr,
	&dyn_fsync_version_attr.attr,
	&dyn_fsync_version_attr_lower.attr,
	NULL,
};

static struct attribute_group dyn_fsync_attr_group = {
	.attrs = dyn_fsync_attrs,
};

static struct kobject *dyn_fsync_kobj;

static int __init dynamic_fsync_init(void)
{
	int ret;

	dyn_fsync_wq = alloc_workqueue("dyn_fsync_wq", WQ_HIGHPRI | WQ_UNBOUND, 1);
	if (!dyn_fsync_wq) {
		pr_err("dyn_fsync: failed to create workqueue\n");
		return -ENOMEM;
	}

	INIT_WORK(&dyn_fsync_work, dyn_fsync_work_fn);

	dyn_fsync_kobj = kobject_create_and_add("dyn_fsync", kernel_kobj);
	if (!dyn_fsync_kobj) {
		pr_err("dyn_fsync: failed to create sysfs object\n");
		destroy_workqueue(dyn_fsync_wq);
		return -ENOMEM;
	}

	ret = sysfs_create_group(dyn_fsync_kobj, &dyn_fsync_attr_group);
	if (ret) {
		pr_err("dyn_fsync: failed to create sysfs group\n");
		kobject_put(dyn_fsync_kobj);
		destroy_workqueue(dyn_fsync_wq);
		return ret;
	}

#ifdef CONFIG_FB
	fb_register_client(&dyn_fsync_notifier);
#endif

	pr_info("dyn_fsync: Dynamic Fsync v%s initialized\n", DYN_FSYNC_VERSION);
	return 0;
}
late_initcall(dynamic_fsync_init);
