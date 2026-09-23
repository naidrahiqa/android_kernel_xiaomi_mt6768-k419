### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers
## Mocchipyon Kernel — MediaTek-safe version

### AnyKernel setup
# begin properties
properties() { '
kernel.string=Mocchipyon Kernel — by @Naidrahiqa
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=selene
device.name2=selenes
device.name3=selene_global
device.name4=selenes_global
device.name5=merlin
device.name6=Merlin
device.name7=merlinx
device.name8=Merlinx
device.name9=lancelot
device.name10=Lancelot
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties

### AnyKernel install
# begin attributes
boot_attributes() {
set_perm_recursive 0 0 755 644 $RAMDISK/*;
set_perm_recursive 0 0 750 750 $RAMDISK/init* $RAMDISK/sbin;
} # end attributes

## boot shell variables
block=auto;
is_slot_device=1;
ramdisk_compression=auto;
# CRITICAL for MediaTek:
# Do NOT patch vbmeta — HyperOS/MIUI validates boot chain.
# Patching vbmeta can cause verification failure → brick.
patch_vbmeta_flag=0;

# Kaeru LK support
do_kaeru=0;
kaeru_lk="lk_a.img";

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

## boot install
# dump_boot: unpacks boot image into $KERNEL and $RAMDISK
# This preserves original ramdisk, DTB, and boot header
dump_boot;

# write_boot: repacks $KERNEL + $RAMDISK into boot image and flashes
# Ramdisk is completely untouched — only kernel is replaced
write_boot;

## Kaeru LK install
# Flash Kaeru LK if available
if [ "$do_kaeru" = "1" ] && [ -f "$kaeru_lk" ]; then
    ui_print "- Flashing Kaeru LK to lk_a partition..."
    # Determine slot suffix for A/B devices
    SLOT=""
    if [ "$is_slot_device" = "1" ]; then
        SLOT=$(getprop ro.boot.slot_suffix 2>/dev/null || echo "_a")
    fi
    LK_DEV="/dev/block/by-name/lk${SLOT}"
    if [ -e "$LK_DEV" ]; then
        dd if="$kaeru_lk" of="$LK_DEV" bs=4096
        ui_print "- Kaeru LK flashed to $LK_DEV"
    else
        ui_print "- Warning: $LK_DEV not found, skipping LK flash"
    fi
fi;
## end boot install
