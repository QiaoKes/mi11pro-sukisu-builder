#!/usr/bin/env bash
set -euo pipefail

kernel_dir=${1:?kernel source directory is required}
mode=${2:?build mode is required}
enable_kpm=${3:-false}
enable_susfs=${4:-false}
susfs_commit=${5:-not-applicable}
workspace=$(pwd)
out_dir="$workspace/out"
release_dir="$workspace/release"

test -s "$out_dir/arch/arm64/boot/Image"
test -s "$out_dir/.config"
grep -q '^CONFIG_BOARD_XIAOMI_STAR=y$' "$out_dir/.config"

if [[ "$mode" == "sukisu" ]]; then
  grep -q '^CONFIG_KSU=y$' "$out_dir/.config"
  if [[ "$enable_susfs" == "true" ]]; then
    grep -q '^CONFIG_KSU_SUSFS=y$' "$out_dir/.config"
    grep -q '^CONFIG_KSU_SUSFS_SUS_PATH=y$' "$out_dir/.config"
    grep -q '^CONFIG_KSU_SUSFS_SUS_MOUNT=y$' "$out_dir/.config"
    grep -q '^CONFIG_KSU_SUSFS_SUS_KSTAT=y$' "$out_dir/.config"
    grep -q '^# CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG is not set$' "$out_dir/.config"
  else
    grep -q '^# CONFIG_KSU_SUSFS is not set$' "$out_dir/.config"
  fi
  if [[ "$enable_kpm" == "true" ]]; then
    grep -q '^CONFIG_KPM=y$' "$out_dir/.config"
  else
    grep -q '^# CONFIG_KPM is not set$' "$out_dir/.config"
  fi
else
  grep -q '^# CONFIG_KSU is not set$' "$out_dir/.config"
fi

zip_path=$(find "$out_dir/anykernel" -maxdepth 1 -type f -name '*.zip' -print -quit)
test -n "$zip_path"

mkdir -p "$release_dir"
cp "$zip_path" "$release_dir/"
cp "$out_dir/arch/arm64/boot/Image" "$release_dir/Image"
cp "$out_dir/.config" "$release_dir/kernel.config"
cp "$workspace/build.log" "$release_dir/build.log"

kernel_commit=$(git -C "$kernel_dir" rev-parse HEAD)
sukisu_commit=not-applicable
if [[ -d "$kernel_dir/KernelSU/.git" ]]; then
  sukisu_commit=$(git -C "$kernel_dir/KernelSU" rev-parse HEAD)
fi

{
  echo "device=Xiaomi Mi 11 Pro"
  echo "codename=mars"
  echo "kernel_target=star"
  echo "mode=$mode"
  echo "kpm=$enable_kpm"
  echo "susfs=$enable_susfs"
  echo "kernel_source=https://github.com/EndCredits/android_kernel_xiaomi_sm8350-miui"
  echo "kernel_commit=$kernel_commit"
  echo "sukisu_source=https://github.com/SukiSU-Ultra/SukiSU-Ultra"
  echo "sukisu_commit=$sukisu_commit"
  echo "susfs_source=https://gitlab.com/simonpunk/susfs4ksu"
  echo "susfs_commit=$susfs_commit"
  echo "toolchain=AOSP clang-r383902b1"
} > "$release_dir/build-info.txt"

(
  cd "$release_dir"
  sha256sum ./* > SHA256SUMS
)

echo "Release files:"
find "$release_dir" -maxdepth 1 -type f -print
