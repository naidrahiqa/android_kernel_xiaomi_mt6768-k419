// SPDX-License-Identifier: GPL-2.0
/*
 * KCAL - Advanced color control for MediaTek MT6768 CCORR
 *
 * Implements the standard KCAL sysfs interface compatible with
 * Franco Kernel Manager, SmartPack, and KCAL app.
 *
 * Copyright (C) 2013-2015 savoca
 * Adapted for MediaTek MT6768 hardware CCORR
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/platform_device.h>
#include <linux/device.h>
#include <linux/string.h>
#include <ddp_gamma.h>

#define KCAL_VERSION "1.0"

static int kcal_r = 256;
static int kcal_g = 256;
static int kcal_b = 256;
static int kcal_enable = 1;
static int kcal_min = 0;
static int kcal_invert = 0;

static void kcal_apply(void)
{
	int r, g, b;

	if (!kcal_enable) {
		disp_ccorr_set_RGB_Gain(1024, 1024, 1024);
		return;
	}

	/* Scale 0-256 to 0-1024 */
	r = clamp(kcal_r * 4, 0, 1024);
	g = clamp(kcal_g * 4, 0, 1024);
	b = clamp(kcal_b * 4, 0, 1024);

	disp_ccorr_set_RGB_Gain(r, g, b);
}

static ssize_t kcal_show(struct device *dev,
			 struct device_attribute *attr, char *buf)
{
	return sprintf(buf, "%d %d %d\n", kcal_r, kcal_g, kcal_b);
}

static ssize_t kcal_store(struct device *dev,
			  struct device_attribute *attr,
			  const char *buf, size_t count)
{
	int r, g, b;

	if (sscanf(buf, "%d %d %d", &r, &g, &b) != 3)
		return -EINVAL;

	kcal_r = clamp(r, 0, 256);
	kcal_g = clamp(g, 0, 256);
	kcal_b = clamp(b, 0, 256);

	kcal_apply();
	return count;
}

static ssize_t kcal_enable_show(struct device *dev,
				struct device_attribute *attr, char *buf)
{
	return sprintf(buf, "%d\n", kcal_enable);
}

static ssize_t kcal_enable_store(struct device *dev,
				 struct device_attribute *attr,
				 const char *buf, size_t count)
{
	unsigned int val;

	if (kstrtouint(buf, 0, &val) < 0)
		return -EINVAL;

	kcal_enable = (val != 0);
	kcal_apply();
	return count;
}

static ssize_t kcal_min_show(struct device *dev,
			     struct device_attribute *attr, char *buf)
{
	return sprintf(buf, "%d\n", kcal_min);
}

static ssize_t kcal_min_store(struct device *dev,
			      struct device_attribute *attr,
			      const char *buf, size_t count)
{
	unsigned int val;

	if (kstrtouint(buf, 0, &val) < 0)
		return -EINVAL;

	kcal_min = clamp_t(int, val, 0, 256);
	return count;
}

static ssize_t kcal_invert_show(struct device *dev,
				struct device_attribute *attr, char *buf)
{
	return sprintf(buf, "%d\n", kcal_invert);
}

static ssize_t kcal_invert_store(struct device *dev,
				 struct device_attribute *attr,
				 const char *buf, size_t count)
{
	unsigned int val;

	if (kstrtouint(buf, 0, &val) < 0)
		return -EINVAL;

	kcal_invert = (val != 0);
	return count;
}

static DEVICE_ATTR_RW(kcal);
static DEVICE_ATTR_RW(kcal_enable);
static DEVICE_ATTR_RW(kcal_min);
static DEVICE_ATTR_RW(kcal_invert);

static struct attribute *kcal_attrs[] = {
	&dev_attr_kcal.attr,
	&dev_attr_kcal_enable.attr,
	&dev_attr_kcal_min.attr,
	&dev_attr_kcal_invert.attr,
	NULL,
};

static const struct attribute_group kcal_group = {
	.attrs = kcal_attrs,
};

static const struct attribute_group *kcal_groups[] = {
	&kcal_group,
	NULL,
};

static struct platform_device kcal_dev = {
	.name = "kcal_ctrl",
	.id = 0,
	.dev = {
		.groups = kcal_groups,
	},
};

static int __init kcal_init(void)
{
	int ret;

	ret = platform_device_register(&kcal_dev);
	if (ret) {
		pr_err("kcal: failed to register platform device (%d)\n", ret);
		return ret;
	}

	pr_info("kcal: MediaTek Hardware KCAL v%s initialized\n", KCAL_VERSION);
	return 0;
}
late_initcall(kcal_init);
