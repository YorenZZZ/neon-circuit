# 构建与发布 / Build and distribution

当前 **0.1.0 preview** 的应用 ZIP 和 DMG 使用 ad hoc 签名，尚未获得 Developer ID 签名与 Apple 公证。用户首次打开时可能需要为这个应用单独批准；安装步骤与三张操作示意图见 [README](../README.md#首次打开在隐私与安全中允许)。发行包入口为 [0.1.0 预览版 Release](https://github.com/YorenZZZ/neon-circuit/releases/tag/v0.1.0-preview)。后续可另行提供 Developer ID 签名及公证版本，减少首次打开时的操作。

## 本地构建

需要 macOS 与 Xcode Command Line Tools。预置的主题、图标和 PNG 示例图参与打包，构建不需要重新生成图形，也不需要 Node.js、Python 或第三方库。

```sh
xcode-select --install
./scripts/build.sh
open "build/NEON Circuit.app"
./scripts/package.sh
```

`xcode-select --install` 只需在缺少 Command Line Tools 时执行。

| 产物 | 内容 |
| --- | --- |
| `build/NEON Circuit.app` | 应用、光标辅助程序、主题和图标。 |
| `dist/NEON-Circuit-0.1.0-preview-universal.zip` | 可解压的测试应用包。 |
| `dist/NEON-Circuit-0.1.0-preview-universal.dmg` | 可拖进 Applications 的测试磁盘映像。 |

打包脚本只生成本地文件，不会自行上传或发布。构建目标为 `arm64` 与 `x86_64` 的 Universal 应用；实际平台验证范围见 [compatibility.md](compatibility.md)。GitHub 自动产生的源码 ZIP 与这里的应用 ZIP 是不同产物。

## 无证书时的单应用批准

Developer ID 证书不是运行本机编译应用的前提。若 macOS 27 阻止打开来源可信且未被篡改的未公证应用，应先尝试打开应用，再进入 **系统设置 → 隐私与安全 → 安全性**，依次点击 **打开（Open）→ 仍要打开（Open Anyway）**，输入登录密码并点 **好（OK）**。按钮在首次尝试后一小时内可用；批准后系统保存该应用的例外，之后通常可双击打开。设备管理策略可能限制此选项。[Apple macOS 27 官方说明](https://support.apple.com/zh-cn/guide/mac-help/mh40616/mac)

这种批准不等于 Developer ID 签名或公证，也不会改变项目的系统兼容范围。它适用于来源可信的未公证或无法验证开发者提示；“已损坏”“将损坏电脑”或检测到恶意软件的告警需要停止安装并核对来源，不能按同一教程继续打开。

## Preview 发布条件

确认两种二进制架构、主题文件和 ad hoc 签名，运行当前已支持系统上的必要检查，在发行包中附带说明书和校验值。Release 必须明确标注 **preview、ad hoc、未公证**，并提供单应用批准教程及已测试平台说明。保留正常系统安全检查，不要求关闭 Gatekeeper 或 SIP。

## 后续 Developer ID 签名发行

提供已识别开发者且完成公证的版本，需要有 Apple Developer ID Application 签名身份，并为应用及其辅助可执行文件完成适当签名、Hardened Runtime 和公证流程。Apple 的公证工具为 `notarytool` 和 `stapler`。[Apple Developer ID](https://developer.apple.com/developer-id/) · [Apple 公证文档](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

发布顺序：

1. 从确认的源码版本构建，验证主题文件和两种二进制架构。
2. 完成已支持系统上的应用、回读核对、恢复核对与菜单操作验证；未测试的平台明确标注。
3. 从辅助程序到外层应用依次使用 Developer ID 签名，并验证签名结果。
4. 提交 Apple 公证，确认 `Accepted`，将公证票据附加到合适的发行产物，再核对票据。
5. 打包最终应用，记录 SHA-256；签名完成后不再更改应用内容。
6. 用正常下载流程获取最终包，在保持 Gatekeeper 开启的 Mac 上验证解压或挂载、拖入 Applications、首次打开和自动应用流程。
7. 在 Release 中写明版本、签名与公证状态、已测试系统、未测试平台、安装和恢复方式，以及已知限制。

正式发行应保持系统的正常安全检查，不要求用户关闭 Gatekeeper 或 SIP。本项目说明书不提供移除下载隔离属性的绕过步骤。[Apple 的下载应用检查说明](https://support.apple.com/en-us/102445)

签名证书、私钥、Apple 账户凭证、公证凭证、个人备份和本机操作日志不得进入源码仓库或 Release。完整源代码与原创主题可以公开；每个用户的恢复基线只能由应用在该用户本机建立。

## Release 文案应说明的行为

用户下载 ZIP 或 DMG，将应用放进 Applications 后自行打开。首次打开执行备份、应用和核对。下载本身不会执行程序。登录时启动默认关闭，由用户在菜单栏勾选。

恢复操作使用首次保存的光标基线，并停止后续自动应用。退出应用会保留当前会话中的光标。原生等待彩球、软件自绘光标和登录前界面不在覆盖范围内。

## English summary

Use `./scripts/build.sh` and `./scripts/package.sh` on macOS with Apple's Command Line Tools. Included theme, icon, and PNG assets require no Node.js, Python, or additional library installation. The app builds to `build/`; preview ZIP and DMG packages go to `dist/`.

The current 0.1.0 preview ZIP and DMG are ad hoc signed and unnotarized. Clearly label that status in the Release, include checksums, and provide the first-launch illustrations in the README. A future notarized release needs Developer ID signing, Hardened Runtime, accepted notarization, appropriate stapling, and validation through a normal download with Gatekeeper enabled. Signing and notarization credentials, user cursor backups, and local operation logs must never be distributed.

For a trusted unnotarized app blocked by macOS 27, first try opening it. Then go to **System Settings → Privacy & Security → Security**, click **Open → Open Anyway**, enter your login password, and click **OK**. Managed devices may restrict it. Do not apply this tutorial to damaged-app or detected-malware alerts. Approval is not notarization or a broader compatibility guarantee. [Apple's macOS 27 guide](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac).

Installation means downloading, moving the app into Applications, and explicitly opening it. The first launch performs backup, application, and verification. Launch at Login is opt-in. A Release must state its signing status, tested OS builds and chips, unsupported scope, and recovery steps.
