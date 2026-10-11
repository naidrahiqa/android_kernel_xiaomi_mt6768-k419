#!/bin/bash
set -euo pipefail
cd "${GITHUB_WORKSPACE}"
mkdir -p artifacts

variants=(
  "xxksu-nomount|||xxksu-nomount"
  "xxksu|CONFIG_NOMOUNT=n|xxksu"
  "bakasu-nomount|CONFIG_KSU_XXKSU=n CONFIG_KSU_BAKASU=y CONFIG_KSU_MANUAL_HOOK=y CONFIG_KSU_HOSTSREDIRECT=y|bakasu-nomount"
  "bakasu|CONFIG_KSU_XXKSU=n CONFIG_KSU_BAKASU=y CONFIG_KSU_MANUAL_HOOK=y CONFIG_KSU_HOSTSREDIRECT=y CONFIG_NOMOUNT=n|bakasu"
)

for v in "${variants[@]}"; do
  IFS='|' read -r variant config_override zip_suffix <<< "$v"
  echo "=== Building $variant ==="
  
  DEFCONFIG=selene_defconfig \
  EXTRA_MAKE_ARGS="LLVM=1 LLVM_IAS=1" \
  CONFIG_OVERRIDES="$config_override" \
  ARCH=arm64 \
  KERNEL_PATH=. \
  TOOLCHAIN=greenforce-clang \
  USE_CCACHE=true \
  CCACHE_SIZE=2G \
  JOBS=$(nproc) \
  CROSS_COMPILE=aarch64-linux-gnu- \
  CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
  OUT_DIR=out_${variant} \
  BUILD_LOG=build_${variant}.log \
  "${GITHUB_WORKSPACE}/kit/scripts/build-kernel.sh"
  
  DEVICE_NAME=selene \
  KERNEL_PATH=. \
  KERNEL_VERSION=$(make -s O=out_${variant} ARCH=arm64 kernelrelease 2>>build_${variant}.log | tail -n1) \
  ANYKERNEL_BRANCH=dca9dc3 \
  ZIP_NAME_TEMPLATE="PawwwNunungggg-${zip_suffix}-R${GITHUB_RUN_NUMBER}-{hash}-{date}" \
  TOOLCHAIN=greenforce-clang \
  "${GITHUB_WORKSPACE}/kit/scripts/package-anykernel.sh"
  
  mv *.zip artifacts/ 2>/dev/null || true
  mv *.zip.sha256 artifacts/ 2>/dev/null || true
done

echo "zips=$(ls artifacts/*.zip | tr '\n' ' ')" >> "$GITHUB_OUTPUT"
