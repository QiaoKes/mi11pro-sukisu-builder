# Mi 11 Pro SukiSU Kernel Builder

为 Xiaomi Mi 11 Pro（`mars / M2102K1AC`）的 MIUI 14 内核构建可测试的
SukiSU Ultra 内核与 AnyKernel3 刷机包。

## 固定基线

- 设备：Xiaomi Mi 11 Pro（`mars`）
- 共享内核目标：`star`
- 系统基线：MIUI 14 / Android 13
- 当前设备内核：`5.4.233-qgki`
- 内核源码：[EndCredits/android_kernel_xiaomi_sm8350-miui](https://github.com/EndCredits/android_kernel_xiaomi_sm8350-miui)
- SukiSU：[SukiSU-Ultra/SukiSU-Ultra](https://github.com/SukiSU-Ultra/SukiSU-Ultra)
- 工具链：AOSP Clang `r383902b1`

工作流固定内核源码提交，并通过 SukiSU 官方 `kernel/setup.sh` 集成
`builtin` 分支。默认启用 `CONFIG_KSU=y`，关闭 KPM，不包含 SUSFS。

## 构建

1. 打开仓库的 **Actions** 页面。
2. 选择 **Build Mi 11 Pro SukiSU kernel**。
3. 点击 **Run workflow**。
4. 第一次建议运行 `baseline`，确认该内核树能为当前 ROM 产出完整包。
5. 再运行 `sukisu`，保持 KPM 关闭。
6. 构建完成后下载 `mi11pro-...` Artifact。

Artifact 包含：

- `Hana-kernel-star-*.zip`：限制 `mars/star` 设备的 AnyKernel3 包
- `Image`：编译出的内核镜像
- `kernel.config`：最终内核配置
- `build-info.txt`：上游提交和工具链信息
- `SHA256SUMS`：文件校验值
- `build.log`：完整编译日志

## 集成方式

目标内核已启用 `CONFIG_KPROBES=y`、`CONFIG_KALLSYMS_ALL=y` 和
`CONFIG_EXT4_FS=y`。工作流按照
[SukiSU 官方集成指南](https://github.com/SukiSU-Ultra/SukiSU-Ultra/blob/main/docs/guide/how-to-integrate.md)
执行官方针对 built-in / non-GKI 内核指定的命令：

```sh
curl -LSs \
  "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh" \
  | bash -s builtin
```

源码原有的旧 KernelSU 子模块会先被移除，避免官方脚本误用旧仓库。
`builtin` 分支自身提供 Android 5.4 所需的 seccomp、fsnotify、SELinux 和
nofault API 兼容层，构建器不再修改 SukiSU 实现。工作流会检查实际检出的分支，
防止误用只面向新 GKI 的主线代码。

SukiSU `builtin` 的 Kconfig 默认可能打开 SUSFS；本项目会显式写入
`# CONFIG_KSU_SUSFS is not set`，确保第一轮产物只包含 SukiSU 核心。

完整编译前会先生成内核编译元数据和 SELinux 头文件，再单独编译
`drivers/kernelsu/`，用于快速验证 SukiSU 与目标 5.4 内核的 API 兼容性。
该步骤通过后才开始完整内核构建。

工作流缓存固定 Clang 工具链和 `out/` 中间对象。缓存键包含内核提交、SukiSU
`builtin` 的实际提交、构建模式、KPM 设置和准备脚本摘要。失败构建也会用本次
运行的唯一键保存已完成对象；后续运行先恢复最新兼容缓存，只重编变化部分。

## 安全边界

编译成功只说明源码和工具链可用，不代表内核已经在这台手机上验证可启动。

- 不要在未备份 `boot_a`、`boot_b` 和 `vbmeta` 前刷写。
- 不要锁回 Bootloader。
- 第一轮不启用 KPM 或 SUSFS。
- 不要同时向两个槽位刷入测试内核。
- 保留当前可启动的 Magisk 槽位作为回退路径。
- 如果设备支持，优先使用 `fastboot boot` 临时测试；否则只测试非当前槽位并确保能用 fastboot 切回。

本仓库只提供可复现的构建流程，不声明生成物已通过真机验证。
