#!/usr/bin/env bash
set -euo pipefail

kernel_dir=${1:?kernel source directory is required}
mode=${2:?build mode is required}
sukisu_ref=${3:?SukiSU ref is required}
enable_kpm=${4:-false}

cd "$kernel_dir"

case "$mode" in
  baseline)
    git submodule update --init --depth=1 KernelSU
    ;;
  sukisu)
    rm -rf KernelSU

    # This is the integration command prescribed by SukiSU's official guide.
    curl -LSs \
      "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh" \
      | bash -s "$sukisu_ref"

    test "$(git -C KernelSU remote get-url origin)" = \
      "https://github.com/SukiSU-Ultra/SukiSU-Ultra"

    # SukiSU v4.1.3 includes this newer header without using any declaration
    # from it. Android 5.4 GKI 1.0 has only arch/arm64/include/asm/pgtable.h.
    if [[ ! -e include/linux/pgtable.h ]]; then
      sed -i \
        '/#include <linux\/pgtable.h>/d' \
        KernelSU/kernel/feature/sucompat.c
    fi
    ;;
  *)
    echo "Unsupported build mode: $mode" >&2
    exit 2
    ;;
esac

defconfig=arch/arm64/configs/vendor/star_defconfig
sed -i -E \
  '/^(# )?CONFIG_(KSU|KSU_DEBUG|KPM)(=| is not set)/d' \
  "$defconfig"

if [[ "$mode" == "sukisu" ]]; then
  printf '\nCONFIG_KSU=y\n# CONFIG_KSU_DEBUG is not set\n' >> "$defconfig"
  if [[ "$enable_kpm" == "true" ]]; then
    printf 'CONFIG_KPM=y\n' >> "$defconfig"
  else
    printf '# CONFIG_KPM is not set\n' >> "$defconfig"
  fi
else
  printf '\n# CONFIG_KSU is not set\n' >> "$defconfig"
fi

# The upstream packager disables device checks. Restrict generated ZIPs to the
# shared Mi 11 Pro/Ultra star kernel family before they leave CI.
anykernel=scripts/ak3/anykernel.sh
sed -i 's/do.devicecheck=0/do.devicecheck=1/' "$anykernel"
sed -i \
  's/device.name1=DEVICE_PLACEHOLDER/device.name1=mars\ndevice.name2=star/' \
  "$anykernel"
sed -i \
  "s/kernel.string=.*/kernel.string=Mi 11 Pro (mars) $mode kernel/" \
  "$anykernel"

grep -q '^CONFIG_KPROBES=y$' "$defconfig"
grep -q '^CONFIG_KALLSYMS_ALL=y$' "$defconfig"
grep -q '^CONFIG_EXT4_FS=y$' "$defconfig"
grep -q '^do.devicecheck=1$' "$anykernel"
grep -q '^device.name1=mars$' "$anykernel"

echo "Kernel source prepared for $mode (KPM: $enable_kpm)."
