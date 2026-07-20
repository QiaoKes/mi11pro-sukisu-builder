#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
builder_dir=$(cd -- "$script_dir/.." && pwd)
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

    # This 5.4 tree has the pre-rename no-fault user string helper. Select it
    # only when the newer API is absent and the compatible API is declared.
    if ! grep -q 'strncpy_from_user_nofault' include/linux/uaccess.h \
      && grep -q 'strncpy_from_unsafe_user' include/linux/uaccess.h; then
      find KernelSU/kernel -type f \( -name '*.c' -o -name '*.h' \) \
        -exec sed -i \
          's/strncpy_from_user_nofault/strncpy_from_unsafe_user/g' {} +
    fi

    if ! grep -q 'copy_to_kernel_nofault' include/linux/uaccess.h \
      && grep -q 'probe_kernel_write' include/linux/uaccess.h; then
      find KernelSU/kernel -type f \( -name '*.c' -o -name '*.h' \) \
        -exec sed -i \
          's/copy_to_kernel_nofault/probe_kernel_write/g' {} +
    fi

    if ! grep -q 'copy_from_user_nofault' include/linux/uaccess.h \
      && grep -q 'probe_user_read' include/linux/uaccess.h; then
      find KernelSU/kernel -type f \( -name '*.c' -o -name '*.h' \) \
        -exec sed -i \
          's/copy_from_user_nofault/probe_user_read/g' {} +
    fi

    if ! grep -q 'copy_to_user_nofault' include/linux/uaccess.h \
      && grep -q 'probe_user_write' include/linux/uaccess.h; then
      find KernelSU/kernel -type f \( -name '*.c' -o -name '*.h' \) \
        -exec sed -i \
          's/copy_to_user_nofault/probe_user_write/g' {} +
    fi

    if ! grep -q 'security_inode_init_security_anon' include/linux/security.h; then
      patch --directory=KernelSU --strip=1 --forward \
        < "$builder_dir/patches/sukisu-android-5.4-anon-inode.patch"
    fi

    if ! grep -Rqs 'SECCOMP_ARCH_NATIVE_NR' kernel/seccomp.c include; then
      patch --directory=KernelSU --strip=1 --forward \
        < "$builder_dir/patches/sukisu-android-5.4-seccomp-no-cache.patch"
    fi

    if ! grep -q 'handle_inode_event' include/linux/fsnotify_backend.h; then
      patch --directory=KernelSU --strip=1 --forward \
        < "$builder_dir/patches/sukisu-android-5.4-fsnotify.patch"
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
