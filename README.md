# AGY Go

Google [Antigravity CLI (`agy`)](https://github.com/google-antigravity/antigravity-cli) 的 Android 手机客户端、本机运行环境与全功能助手。

## 核心能力

- **手机本机直接运行（Android 8+，`arm64-v8a`，免 Root、免 Termux）**
  - 默认原生模式：直接拉取并校验（SHA-512）Google 官方发布的 Android 原生 Bionic `agy` 二进制，由 Android 前台服务（`AgyService`）托管 `agy acp` 并通过随机令牌鉴权的 `127.0.0.1` 回环桥接给 Flutter，锁屏/切后台不断流。
  - 可选 PRoot Linux 容器模式：通过 `runtime/build-rootfs.sh` 可选打包 Ubuntu 24.04 rootfs + Termux PRoot，满足完整 `apt`/`git`/`python3` 工具链或 `x86_64` 模拟器需求。
  - 双认证支持：官方 Google OAuth 登录（`agy acp --login` 浏览器授权流）与 `GEMINI_API_KEY`（可选自定义 `GOOGLE_GEMINI_BASE_URL`）。
- **SSH 远程遥控电脑 / 服务器**
  - 基于 `dartssh2` 通过 SSH `exec` 直跑远端 `agy acp`（支持密码/私钥、Host Key 指纹钉死，远端无需开放额外端口），并在「本机引擎 / SSH 主机」之间一键切换。
  - 内置工作区文件管理器（本机文件系统 + SSH SFTP 浏览与在线编辑）及 `xterm` 交互终端（SSH PTY + 本机 Shell）。
- **MCP 手机操控（原生 Android 无障碍 + SafetyGate 三档安全门）**
  - 内置标准 MCP Streamable HTTP 服务（`PhoneMcpServer.kt`，Bearer 鉴权），自动通过 ACP `mcpServers` 与 `settings.json` 挂载给本机 `agy`，无需修改引擎二进制。
  - 8 项手机工具：`phone_get_screen`、`phone_screenshot`、`phone_tap`、`phone_swipe`、`phone_input_text`、`phone_press_key`、`phone_launch_app`、`phone_list_apps`。
  - `SafetyGate` 三档确认 + 金融/支付/密码应用及敏感关键词强制拦截 + 紧急停止按钮 + 审计日志。
- **语音、原创桌宠、分享回放与系统集成**
  - **语音输入与朗读**：原生 Android `SpeechRecognizer` 语音转文字 + `TextToSpeech` 回复朗读。
  - **原创伴侣「星灵 Starling」**：App 内可拖拽悬浮伙伴 + Android 系统桌面悬浮球（`SYSTEM_ALERT_WINDOW`，靠边吸附），实时同步思考/执行/审批/完成状态。
  - **分享卡与对话回放**：自动脱敏密钥/Token 的高分辨率 PNG 分享卡（FileProvider 原生分享）、Markdown 导出、JSON 回放包导出与内置回放器。
  - **后台保活与自更新**：小米/华为/荣耀/OPPO/vivo/三星省电豁免与厂商自启动直达引导 + GitHub Releases APK 自更新。
  - **雾面玻璃三栏外壳与工作区挂载**：直接采用并适配 [DSH Go](https://github.com/ccch1mneyyy/dsh-go)（GNU AGPL-3.0）的 Mist Glass 雾面玻璃设计语言、6 套 OKLCH 配色、左抽屉 + 浮动顶栏/底栏 + 右快捷面板手势架构、设置枢纽与「全部功能」页；支持多工作区注册、置顶、分组、两步目录选择器，以及 Android 手机共享存储挂载（`targetSdk = 28` + `PhoneStorage` + 原生 Bionic `~/手机存储` 软链 + PRoot `-b /storage/emulated/0:/sdcard` + 托管 `.gemini/GEMINI.md` 路径提示 + ACP `session/new` `cwd` 精确绑定）。品牌图形与「星灵」伴侣为 AGY Go 原创，不包含 DSH Go 专有品牌/吉祥物素材。

## 仓库结构

```text
agy-go/
├── packages/acp_client/     # 纯 Dart Agent Client Protocol (ACP) JSON-RPC 2.0 客户端 + ChatTranscript 折叠器
├── packages/agy_remote/     # 传输层：Android 本机回环令牌桥接 + SSH exec `agy acp`（含指纹钉死）
├── app/                     # Flutter Android 应用（Riverpod 3 + DSH Go Mist Glass UI + Kotlin 原生运行时 / 手机存储挂载 / MCP 手机操控 / 语音 / 桌宠 / 保活更新）
├── runtime/                 # 可选 PRoot Ubuntu 24.04 Linux 容器构建脚本（build-rootfs.sh）
├── tooling/                 # Android APK 打包脚本（build-apk.sh）
├── docs/architecture.md     # 完整架构设计文档
├── THIRD_PARTY_NOTICES.md   # 第三方开源组件与版权声明
└── .github/workflows/ci.yml # Dart/Flutter 静态分析、单元测试与 Android APK 构建 CI
```

## 快速构建与验证

```bash
# 1. 纯 Dart 协议与传输包测试
(cd packages/acp_client && dart pub get && dart analyze && dart test)
(cd packages/agy_remote && dart pub get && dart analyze && dart test)

# 2. Flutter 应用静态检查与测试
(cd app && flutter pub get && flutter analyze && flutter test)

# 3. 构建 Android arm64 APK
bash tooling/build-apk.sh --release --abi arm64

# 4.（可选）构建 PRoot Ubuntu 24.04 Linux 容器资产
bash runtime/build-rootfs.sh arm64-v8a
```

## 致谢与许可

- 本项目以 [GNU AGPL-3.0](LICENSE) 协议开源。
- 雾面玻璃 UI 架构、主题系统、交互组件及 Android 手机存储挂载设计复用并适配自 [DSH Go](https://github.com/ccch1mneyyy/dsh-go)（GNU AGPL-3.0）及其上游组件，详情见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。所有 DSH Go 保留所有权利的品牌与吉祥物素材均未引入，AGY Go 品牌图标与「星灵」伴侣均为原创实现。
- AGY Go 是非官方社区客户端，直连 Google 官方 Antigravity CLI 二进制与官方 ACP 协议，不构成反向代理，与 Google 无隶属关系。
