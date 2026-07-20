#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
builder_dir=$(cd -- "$script_dir/.." && pwd)
kernel_dir=${1:?kernel source directory is required}
mode=${2:?build mode is required}
sukisu_ref=${3:?SukiSU ref is required}
enable_kpm=${4:-false}
enable_susfs=${5:-false}
susfs_dir=${6:-}

if [[ "$mode" == "sukisu" && "$enable_susfs" == "true" ]]; then
  susfs_dir=$(cd -- "${susfs_dir:?SUSFS source directory is required}" && pwd)
fi

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

    test "$(git -C KernelSU branch --show-current)" = "builtin"

    patch --directory=KernelSU --strip=1 --forward \
      < "$builder_dir/patches/sukisu-builtin-5.4-build-fixes.patch"

    # SukiSU's builtin branch is a manual-hook integration for non-GKI
    # kernels. setup.sh wires in the driver; these hooks make it reachable.
    patch --strip=1 --forward \
      < "$builder_dir/patches/sukisu-manual-hooks-5.4.patch"

    if [[ "$enable_susfs" == "true" ]]; then
      susfs_patch="$susfs_dir/Patches/Patch/susfs_patch_to_5.4.patch"
      test -s "$susfs_patch"
      git apply --check --whitespace=nowarn "$susfs_patch"
      git apply --whitespace=nowarn "$susfs_patch"
      grep -Fq '#define SUSFS_VERSION "v2.2.0"' include/linux/susfs.h
    fi
    ;;
  *)
    echo "Unsupported build mode: $mode" >&2
    exit 2
    ;;
esac

defconfig=arch/arm64/configs/vendor/star_defconfig
sed -i.bak -E \
  '/^(# )?CONFIG_(KSU|KSU_DEBUG|KPM|KSU_SUSFS.*)(=| is not set)/d' \
  "$defconfig"
rm -f "$defconfig.bak"

if [[ "$mode" == "sukisu" ]]; then
  printf '\nCONFIG_KSU=y\n# CONFIG_KSU_DEBUG is not set\n' >> "$defconfig"
  if [[ "$enable_kpm" == "true" ]]; then
    printf 'CONFIG_KPM=y\n' >> "$defconfig"
  else
    printf '# CONFIG_KPM is not set\n' >> "$defconfig"
  fi
  if [[ "$enable_susfs" == "true" ]]; then
    cat >> "$defconfig" <<'EOF'
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
# CONFIG_KSU_SUSFS_SPOOF_UNAME is not set
# CONFIG_KSU_SUSFS_ENABLE_LOG is not set
# CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS is not set
# CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG is not set
# CONFIG_KSU_SUSFS_OPEN_REDIRECT is not set
# CONFIG_KSU_SUSFS_SUS_MAP is not set
EOF
  else
    printf '# CONFIG_KSU_SUSFS is not set\n' >> "$defconfig"
  fi
else
  printf '\n# CONFIG_KSU is not set\n' >> "$defconfig"
fi

# The upstream packager disables device checks. Restrict generated ZIPs to the
# shared Mi 11 Pro/Ultra star kernel family before they leave CI.
anykernel=scripts/ak3/anykernel.sh
sed -i.bak 's/do.devicecheck=0/do.devicecheck=1/' "$anykernel"
sed -i.bak \
  's/device.name1=DEVICE_PLACEHOLDER/device.name1=mars\ndevice.name2=star/' \
  "$anykernel"
sed -i.bak \
  "s/kernel.string=.*/kernel.string=Mi 11 Pro (mars) $mode kernel/" \
  "$anykernel"
rm -f "$anykernel.bak"

grep -q '^CONFIG_KPROBES=y$' "$defconfig"
grep -q '^CONFIG_KALLSYMS_ALL=y$' "$defconfig"
grep -q '^CONFIG_EXT4_FS=y$' "$defconfig"
if [[ "$mode" == "sukisu" ]]; then
  if [[ "$enable_susfs" == "true" ]]; then
    grep -q '^CONFIG_KSU_SUSFS=y$' "$defconfig"
    grep -q '^CONFIG_KSU_SUSFS_SUS_PATH=y$' "$defconfig"
    grep -q '^CONFIG_KSU_SUSFS_SUS_MOUNT=y$' "$defconfig"
    grep -q '^CONFIG_KSU_SUSFS_SUS_KSTAT=y$' "$defconfig"
    test -s fs/susfs.c
    test -s include/linux/susfs.h
    test -s include/linux/susfs_def.h
  else
    grep -q '^# CONFIG_KSU_SUSFS is not set$' "$defconfig"
  fi
  grep -Fq 'ksu_handle_execveat(&fd, &filename, &argv, &envp, &flags)' fs/exec.c
  grep -Fq 'ksu_handle_faccessat(&dfd, &filename, &mode, NULL)' fs/open.c
  grep -Fq 'ksu_handle_vfs_read(&file, &buf, &count, &pos)' fs/read_write.c
  grep -Fq 'ksu_handle_stat(&dfd, &filename, &flags)' fs/stat.c
fi
grep -q '^do.devicecheck=1$' "$anykernel"
grep -q '^device.name1=mars$' "$anykernel"

echo "Kernel source prepared for $mode (KPM: $enable_kpm, SUSFS: $enable_susfs)."
