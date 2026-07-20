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

工作流固定内核源码提交，并通过 SukiSU 官方 `kernel/setup.sh` 集成指定标签。
默认构建 SukiSU `v4.1.3`，启用 `CONFIG_KSU=y`，关闭 KPM，不包含 SUSFS。

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
执行：

```sh
curl -LSs \
  "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh" \
  | bash -s v4.1.3
```

源码原有的旧 KernelSU 子模块会先被移除，避免官方脚本误用旧仓库。

SukiSU `v4.1.3` 的 `sucompat.c` 还包含一个未使用的
`linux/pgtable.h`。该头文件不存在于 Android 5.4 GKI 1.0 源码中，工作流仅在
确认头文件缺失时移除这条未使用的 include；不修改 SukiSU 的执行逻辑。

Android 5.4 将无缺页用户字符串读取接口命名为
`strncpy_from_unsafe_user()`；新内核将其重命名为
`strncpy_from_user_nofault()`。工作流检查目标内核实际声明，并在新名称缺失时将
SukiSU 调用切换到 5.4 提供的等价接口。

同理，5.4 的 `probe_kernel_write()`、`probe_user_read()` 和
`probe_user_write()` 分别是新内核 `copy_to_kernel_nofault()`、
`copy_from_user_nofault()` 和 `copy_to_user_nofault()` 的前身。工作流仅在
新接口缺失且旧接口存在时进行对应替换。

## 安全边界

编译成功只说明源码和工具链可用，不代表内核已经在这台手机上验证可启动。

- 不要在未备份 `boot_a`、`boot_b` 和 `vbmeta` 前刷写。
- 不要锁回 Bootloader。
- 第一轮不启用 KPM 或 SUSFS。
- 不要同时向两个槽位刷入测试内核。
- 保留当前可启动的 Magisk 槽位作为回退路径。
- 如果设备支持，优先使用 `fastboot boot` 临时测试；否则只测试非当前槽位并确保能用 fastboot 切回。

本仓库只提供可复现的构建流程，不声明生成物已通过真机验证。
