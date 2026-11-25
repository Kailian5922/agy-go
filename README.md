# AGY Go

Google [Antigravity CLI (`agy`)](https://github.com/google-antigravity/antigravity-cli) 的 Android 手机客户端与本机运行环境。

- **手机本机直接运行（Android 8+，arm64，免 Root、免 Termux）**：直接下载并校验（SHA-512）Google 官方发布的 Android 原生 Bionic `agy` 二进制，由 Android 前台服务（`AgyService`）托管 `agy acp` 进程，并通过令牌鉴权的回环桥接给 Flutter，锁屏/切后台不断流。
- **SSH 远程遥控电脑/服务器**：通过 SSH `exec` 通道直跑远端 `agy acp`（支持密码/私钥、Host Key 指纹钉死，远端无需开放额外端口），一键在「本机引擎」和「SSH 主机」之间切换。
- **原生玻璃拟态三栏外壳**：借鉴 [dsh-Go](https://github.com/ccch1mneyyy/dsh-go) 的雾面玻璃、细线骨架与连续跟手三栏交互理念，全新原创实现 6 套主题配色、流式 Markdown、思考/工具折叠、统一 Diff 视图、交互式权限审批卡片与内置 `xterm` 终端。

## 仓库结构

```text
agy-go/
├── packages/acp_client/     # 纯 Dart Agent Client Protocol (ACP) JSON-RPC 2.0 客户端 + ChatTranscript 折叠器
├── packages/agy_remote/     # 传输层：Android 本机回环令牌桥接 + SSH exec `agy acp`（含指纹钉死）
├── app/                     # Flutter Android 应用（Riverpod 3、玻璃拟态 UI、Kotlin 本机运行时服务）
├── runtime/                 # 可选 PRoot Ubuntu 24.04 Linux 容器模式说明与脚本
├── docs/architecture.md     # 完整架构设计与分阶段路线图（Phase 1 – Phase 4）
└── .github/workflows/ci.yml # Dart/Flutter 静态分析、单元测试与 Android APK 构建 CI
```

## 快速开发与验证

```bash
# 1. 纯 Dart 协议与传输包测试
(cd packages/acp_client && dart pub get && dart analyze && dart test)
(cd packages/agy_remote && dart pub get && dart analyze && dart test)

# 2. Flutter 应用静态检查与组件测试
(cd app && flutter pub get && flutter analyze && flutter test)

# 3. 构建 Android APK（arm64 真机）
(cd app && flutter build apk --release --target-platform android-arm64)
```

## 认证与合规说明

- 本客户端通过官方开放的 **Agent Client Protocol (`agy acp`)** 通信，不修改、也不在仓库或安装包内二次分发 Google 的闭源 `agy` 二进制；首次使用时由用户设备直接从 Google 官方发布清单下载并校验 SHA-512。
- 支持 **Google 账号登录（`agy acp --login` 浏览器授权流）** 与 **Gemini API Key（`modelProvider: gemini` + `GEMINI_API_KEY`，可选自定义 `GOOGLE_GEMINI_BASE_URL`）** 两种方式。

## 路线图

- **Phase 1（已完成基础框架）**：纯 Dart `acp_client`、SSH 远程 `agy acp`、三栏跟手玻璃拟态 UI、流式聊天/Diff/权限审批卡、内置终端、6 套主题色。
- **Phase 2（已完成核心本机直跑服务）**：Android 原生 Bionic `agy` 一键下载/SHA-512 校验/更新、前台服务保活与令牌回环桥接、Google OAuth / API Key 认证管理、实时脱敏日志；后续补充可选 PRoot Ubuntu 完整开发容器与工作区文件浏览器。
- **Phase 3（规划中）**：Android 原生 MCP 手机操控（无障碍读屏点按、Shizuku/ADB 不打扰后台虚拟屏、`SafetyGate` 三档安全确认与金融页拦截）。
- **Phase 4（规划中）**：端上 VAD 语音通话、原创悬浮桌宠与宠物包机制、对话分享卡与加密回放链接、App 自更新与国产 ROM 后台保活引导。

## 致谢与许可

- 代码以 [MIT License](LICENSE) 开源。
- UI 交互结构与 Android `targetSdk = 28` 本机运行思路深受社区优秀项目 [dsh-Go](https://github.com/ccch1mneyyy/dsh-go) 启发，本仓库全部源码、视觉设计与品牌素材均为独立全新编写。
- AGY Go 是非官方社区客户端，与 Google 无隶属关系。
