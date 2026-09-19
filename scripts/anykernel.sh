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
device.name2=Selene
device.name3=merlin
device.name4=Merlin
device.name5=merlinx
device.name6=Merlinx
device.name7=lancelot
device.name8=Lancelot
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
is_slot_device=auto;
ramdisk_compression=auto;
# CRITICAL for MediaTek:
# Do NOT patch vbmeta — HyperOS/MIUI validates boot chain.
# Patching vbmeta can cause verification failure → brick.
patch_vbmeta_flag=0;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

## boot install
# dump_boot: unpacks boot image into $KERNEL and $RAMDISK
# This preserves original ramdisk, DTB, and boot header
dump_boot;

# write_boot: repacks $KERNEL + $RAMDISK into boot image and flashes
# Ramdisk is completely untouched — only kernel is replaced
write_boot;
## end boot install
