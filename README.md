# Mi 11 Pro SukiSU Kernel Builder

为 Xiaomi Mi 11 Pro（`mars / M2102K1AC`）的 MIUI 14 内核构建可测试的
SukiSU Ultra 内核与 AnyKernel3 刷机包。

> [!WARNING]
> 固定的 5.4.283 基线已于 2026-07-21 在 Mi 11 Pro / MIUI 14 上完成真机
> 临时启动测试。即使关闭 ZRAM Dedup，SukiSU 管理器仍未检测到驱动，设备随后
> 出现整机卡死并重启。现有 5.4.283 制品仅供诊断，禁止刷入 boot 分区。

## 固定基线

- 设备：Xiaomi Mi 11 Pro（`mars`）
- 共享内核目标：`star`
- 系统基线：MIUI 14 / Android 13
- 当前设备内核：`5.4.233-qgki`
- 内核源码：[EndCredits/android_kernel_xiaomi_sm8350-miui](https://github.com/EndCredits/android_kernel_xiaomi_sm8350-miui)
- SukiSU：[SukiSU-Ultra/SukiSU-Ultra](https://github.com/SukiSU-Ultra/SukiSU-Ultra)
- 工具链：AOSP Clang `r383902b1`

工作流固定内核源码提交，通过 SukiSU 官方 `kernel/setup.sh` 集成
`builtin` 分支，并按官方 non-GKI 指南接入手动 hook。SukiSU 构建默认启用
`CONFIG_KSU=y`、KPM，以及回移到 Android 5.4 的 SUSFS 2.2.0。

固定的 5.4.283 源码包含一套默认开启的非上游 ZRAM Dedup 实现。真机 minidump
显示内核在 `zram_dedup_put_entry()` 释放交换页时发生致命异常，因此构建流程
强制设置 `# CONFIG_ZRAM_DEDUP is not set`。这只关闭去重扩展，普通 ZRAM 压缩
交换保持启用；产物收集阶段会检查最终 `.config`，防止该设置被其他配置覆盖。

## 构建

1. 打开仓库的 **Actions** 页面。
2. 选择 **Build Mi 11 Pro SukiSU kernel**。
3. 点击 **Run workflow**。
4. 运行 `sukisu`；KPM 和 SUSFS 默认同时开启。
5. 构建完成后下载 `mi11pro-...` Artifact。

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
官方 `setup.sh` 只负责把驱动接入 Kconfig 和 Makefile；`builtin` 用于
non-GKI 时还必须在 `execveat`、`faccessat`、`vfs_read` 和 `stat` 入口调用
SukiSU handler。本项目保存一份仅针对固定 5.4 源码提交的手动 hook 补丁，
并在构建前逐项验证四个调用均已落入目标源码。
`builtin` 分支自身提供 Android 5.4 所需的 seccomp、fsnotify、SELinux 和
nofault API 兼容层。工作流会检查实际检出的分支，防止误用只面向新 GKI 的
主线代码。

当前 `builtin` 分支仍有两处 5.4 编译缺口：低版本排除 SELinux-hide 实现后仍
调用其可选函数，以及 sulog 的空 `user_arg_ptr` 宏类型不匹配。本仓库保存一份
最小补丁，为 `<5.10` 跳过不存在的调用并修正值/指针类型；补丁上下文不匹配时
构建会立即停止，避免上游更新后静默套用错误修改。

SukiSU 40837 使用 SUSFS v2 接口，而官方
[simonpunk/susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu) 的 5.4 分支仍是
v1.5.5。工作流因此固定使用
[NonGKI 5.4 backport](https://github.com/JackA1ltman/NonGKI_Kernel_Build_2nd)
提交 `1ad267cd0a793849127cd549ba460d559017d533` 中的 SUSFS 2.2.0 补丁。补丁在
固定 Xiaomi 源码和 SukiSU Manual Hook 之后先执行完整 `git apply --check`，
任一上下文不匹配都会停止构建。首版只打开 `SUS_PATH`、`SUS_MOUNT` 和
`SUS_KSTAT`；cmdline 伪装、uname 伪装、符号隐藏、open redirect 和 SUS_MAP
保持关闭。

完整编译前会先生成内核编译元数据和 SELinux 头文件，再单独编译
`drivers/kernelsu/`，用于快速验证 SukiSU 与目标 5.4 内核的 API 兼容性。
该步骤通过后才开始完整内核构建。

工作流缓存固定 Clang 工具链和 `out/` 中间对象。缓存键包含内核提交、SukiSU
`builtin` 与 SUSFS 的实际提交、构建模式、KPM/SUSFS 设置和准备脚本摘要。失败构建也会用本次
运行的唯一键保存已完成对象；后续运行只恢复源码和配置完全一致的最新缓存。
恢复后将新检出源码的时间戳归一到对应 Git 提交时间，避免 `make` 因新 Runner
的检出时间较晚而误判所有源码都需要重编。补丁摘要变化时允许回退到同一内核和
SukiSU 提交的旧缓存，但会把所有补丁目标文件重新标记为已修改，确保只重编受影响
的对象并重新链接，不会静默复用旧 hook。

## 安全边界

编译成功只说明源码和工具链可用，不代表内核已经在这台手机上验证可启动。

- 不要在未备份 `boot_a`、`boot_b` 和 `vbmeta` 前刷写。
- 不要锁回 Bootloader。
- KPM + SUSFS 组合产物必须先临时启动并确认管理器驱动状态，再永久刷入。
- 不要同时向两个槽位刷入测试内核。
- 保留当前可启动的 Magisk 槽位作为回退路径。
- 如果设备支持，优先使用 `fastboot boot` 临时测试；否则只测试非当前槽位并确保能用 fastboot 切回。

本仓库只提供可复现的构建流程，不声明生成物已通过真机验证。
