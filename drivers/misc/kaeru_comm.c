// SPDX-License-Identifier: GPL-2.0
/*
 * Kaeru Communication Module
 * 
 * This module provides kernel-side communication with the Kaeru bootloader.
 * Kaeru writes flags to a specific DRAM address before booting the kernel.
 * The kernel reads these flags via __ro_after_init to prevent modification
 * from userspace.
 *
 * Usage:
 *   - Enable CONFIG_KAERU_COMM in kernel config
 *   - Set CONFIG_KAERU_COMM_BASE to the DRAM address used by Kaeru
 *   - The module will read flags during early boot
 *
 * Based on LittleSpammyMailman implementation by @sabrinium0
 */

#include <linux/init.h>
#include <linux/module.h>
#include <linux/io.h>
#include <linux/of.h>
#include <linux/of_address.h>
#include <linux/printk.h>
#include <linux/kaeru_comm.h>

/* Communication structure in DRAM — matches LK layout */
struct kaeru_comm {
    u32 magic;          /* KAERU_MAGIC when Kaeru is active */
    u32 version;        /* Kaeru version */
    u32 flags;          /* Feature flags */
    u32 reserved[13];   /* Padding to 64 bytes */
};

/* Read-only after init - cannot be modified from userspace */
static struct kaeru_comm __ro_after_init kaeru_data;
static bool __ro_after_init kaeru_active;

static int __init kaeru_early_init(void)
{
    struct device_node *np;
    struct resource res;
    void __iomem *base;
    phys_addr_t phys_base;
    struct kaeru_comm __iomem *comm;

    /* Try to find Kaeru communication region from device tree */
    np = of_find_compatible_node(NULL, NULL, "kaeru,comm");
    if (np) {
        if (of_address_to_resource(np, 0, &res) < 0) {
            pr_err("kaeru: failed to get base address from DT\n");
            of_node_put(np);
            return -ENODEV;
        }
        phys_base = res.start;
        of_node_put(np);
    } else {
        /* Fallback to hardcoded address */
        phys_base = CONFIG_KAERU_COMM_BASE;
    }

    /* Map the communication region */
    base = ioremap(phys_base, sizeof(struct kaeru_comm));
    if (!base) {
        pr_err("kaeru: failed to map communication region at 0x%llx\n",
               (u64)phys_base);
        return -ENOMEM;
    }

    comm = (struct kaeru_comm __iomem *)base;

    /* Read magic and validate */
    kaeru_data.magic = readl(&comm->magic);
    if (kaeru_data.magic != KAERU_MAGIC) {
        pr_info("kaeru: no Kaeru LK detected (magic=0x%08x)\n",
                kaeru_data.magic);
        iounmap(base);
        return -ENODEV;
    }

    /* Read version and flags */
    kaeru_data.version = readl(&comm->version);
    kaeru_data.flags = readl(&comm->flags);
    kaeru_active = true;

    pr_info("kaeru: detected v%d.%d.%d (flags=0x%08x)\n",
            (kaeru_data.version >> 16) & 0xFF,
            (kaeru_data.version >> 8) & 0xFF,
            kaeru_data.version & 0xFF,
            kaeru_data.flags);

    /* Log active features */
    if (kaeru_data.flags & KAERU_FLAG_OVERCLOCK)
        pr_info("kaeru: overclock mode active\n");
    if (kaeru_data.flags & KAERU_FLAG_SPOOF_LOCK)
        pr_info("kaeru: lock state spoofing active\n");
    if (kaeru_data.flags & KAERU_FLAG_RECOVERY)
        pr_info("kaeru: recovery mode requested\n");
    if (kaeru_data.flags & KAERU_FLAG_DOWNLOAD)
        pr_info("kaeru: download mode requested\n");

    iounmap(base);
    return 0;
}

/* Export functions for other modules */
bool kaeru_is_active(void)
{
    return kaeru_active;
}
EXPORT_SYMBOL_GPL(kaeru_is_active);

bool kaeru_is_overclock(void)
{
    return kaeru_active && (kaeru_data.flags & KAERU_FLAG_OVERCLOCK);
}
EXPORT_SYMBOL_GPL(kaeru_is_overclock);

bool kaeru_is_spoofing(void)
{
    return kaeru_active && (kaeru_data.flags & KAERU_FLAG_SPOOF_LOCK);
}
EXPORT_SYMBOL_GPL(kaeru_is_spoofing);

bool kaeru_is_recovery(void)
{
    return kaeru_active && (kaeru_data.flags & KAERU_FLAG_RECOVERY);
}
EXPORT_SYMBOL_GPL(kaeru_is_recovery);

bool kaeru_is_download(void)
{
    return kaeru_active && (kaeru_data.flags & KAERU_FLAG_DOWNLOAD);
}
EXPORT_SYMBOL_GPL(kaeru_is_download);

/* Module info */
MODULE_LICENSE("GPL v2");
MODULE_AUTHOR("Mocchipyon Kernel");
MODULE_DESCRIPTION("Kaeru bootloader communication module");
MODULE_VERSION("1.0");

/* Early init, runs before most other subsystems */
subsys_initcall(kaeru_early_init);
