# 兼容性 / Compatibility

NEON Circuit 通过当前登录会话中的系统光标接口工作。macOS 不提供公开、稳定的全局光标主题 API，本项目使用的非公开接口可能随系统更新变化。因此，构建成功、最低部署版本和实际运行兼容性需要分别记录。

## 已知状态

| 平台 | 状态 | 说明 |
| --- | --- | --- |
| Apple Silicon · macOS 27.0（26A428） | 已完成本机验证 | 主题应用、50 个光标注册位回读核对、恢复备份及恢复核对已通过。 |
| Apple Silicon · 其他 macOS 27 构建 | 未实测 | 启动和操作时的接口检查通过不代表已经完成视觉及恢复验证。 |
| Intel · macOS 27 | 未实测 | 发布构建目标包含 x86_64；Universal 二进制不能代替 Intel Mac 实机验证。 |
| macOS 26 及更早版本 | 当前发布不支持应用主题 | 当前接口适配按 macOS 27 设置，应用操作会拒绝不符合要求的系统。 |
| macOS 28 及以后版本 | 未适配 | 需要新版本研究与验证，不承诺继续使用同一接口。 |

编译部署目标为 macOS 14.0，表示二进制使用的编译目标；**它不是 macOS 14 及以上的兼容承诺**。

macOS 的单应用 **Open Anyway** 批准流程只决定是否允许打开应用；它不会改变上述已实测范围，也不会绕过工具的系统与备份兼容性检查。[Apple 官方说明](https://support.apple.com/en-us/102445)

## 应用前检查

工具会在应用前检查系统版本、可用光标接口和预期光标数据，并核对恢复备份。备份记录创建时的系统版本、构建号和架构；环境不符时，应用与恢复都会停止。符合检查条件后才尝试修改当前会话。修改后会读取并核对已写入的数据；应用失败时会尝试恢复备份，并报告恢复核对结果。

接口与数据检查只能确认程序处理的注册位，不代表每款应用、每个显示器或每种特殊光标都经过视觉测试。

## 替换范围

- 当前主题覆盖 50 个系统光标注册位，包括日常指针、文本、抓取、缩放和后台忙碌等状态。多个注册位可以共享同一张图稿。
- 设计图集含 56 种功能设计状态；图集中出现的设计不等于全部注册到系统。
- 原生 macOS 等待彩球保留；后台忙碌动画可替换。
- 软件自行绘制的光标、网页自定义图像光标和游戏准星由软件自身控制。
- FileVault 解锁、登录前界面和其他用户的会话不在替换范围内。
- 其他光标工具再次应用主题时，可能覆盖当前会话的结果。

## 系统更新与反馈

任何 macOS 更新前，建议先使用 **Restore Original Cursors** 恢复光标并关闭 **Launch at Login**。更新后查看对应 Release 的兼容性记录；没有已验证记录时，先保留原生状态。

系统构建号变化后，原来的恢复基线不能直接用于新系统。应用会保留备份，并拒绝自动应用及跨环境恢复。先关闭登录时启动，并保留旧备份；随后按已适配 Release 的升级说明建立新的恢复基线。建立新基线前，需要确认当前会话已是新系统的原生光标，不能把正在使用的主题捕获成“原生备份”。不要用旧系统备份强行恢复新系统。

兼容性反馈请提供芯片型号、macOS 版本及构建号、应用版本、失败操作、菜单栏状态和可复现步骤。提交截图或日志前检查个人信息；不需要上传原生备份文件。

## English summary

Only **Apple Silicon on macOS 27.0 (26A428)** has completed local apply, read-back verification, and restore testing. Other macOS 27 builds and Intel hardware remain untested. The build targets Universal `arm64`/`x86_64`; compiling for an architecture does not validate its runtime behavior.

The macOS 14.0 deployment target is a build setting, not a compatibility guarantee. This release gates theme application to the adapted macOS 27 interface and checks the expected cursor data before mutation. Backups are bound to their OS version/build and architecture; a mismatch blocks application and restoration. Restore and disable Launch at Login before updating macOS. Private interfaces can change with system updates.

The theme covers 50 system registration keys. The 56-state design atlas includes additional designs. Native spinning wait cursors, app-drawn pointers, custom webpage cursors, game crosshairs, FileVault unlock, and pre-login screens remain outside the replacement scope. Report chip, OS version/build, app version, operation, and status when reporting compatibility issues; do not upload personal paths or backup files.
