# AGY Go 架构设计

## 1. 总体分层

```text
┌─────────────────── Android App (Flutter + Kotlin) ───────────────────┐
│ Flutter UI (app/lib/ui/)                                             │
│   ├─ theme/     雾面玻璃、0.75px 细线、6 套主题色、中英双语、边到边   │
│   ├─ shell/     三栏连续跟手手势外壳 + 悬浮星灵伙伴（DraggableInAppPet）│
│   ├─ chat/      流式 Markdown、思考/工具折叠、Diff、审批卡、语音/朗读  │
│   ├─ engine/    本机引擎一键安装/启停/更新/OAuth/API Key/脱敏日志     │
│   ├─ workspace/ 本机文件系统 + SSH SFTP 文件浏览与在线编辑            │
│   ├─ remote/    SSH 主机管理 + xterm 交互终端                        │
│   ├─ phone/     MCP 手机操控管理、SafetyGate 三档确认与审计日志       │
│   ├─ pet/       原创「星灵 Starling」App 内/系统桌面悬浮球设置        │
│   ├─ share/     高分辨率 PNG 分享卡、脱敏 Markdown/JSON 导出与回放器  │
│   └─ system/    国产 ROM 后台保活引导与 GitHub Releases APK 自更新    │
│        │ Riverpod 3 (app/lib/state/)                                 │
│        ▼                                                             │
│ packages/acp_client  (纯 Dart ACP JSON-RPC 2.0 + ChatTranscript)      │
│        │ Pluggable AcpTransport (NDJSON)                             │
│   ┌────┴─────────────────────────┐                                   │
│   ▼                              ▼                                   │
│ LoopbackAcpTransport       SshAcpConnection (packages/agy_remote)    │
│ (127.0.0.1 + 随机 Token)    (dartssh2 exec `agy acp` + 指纹钉死)      │
│   │                                                                  │
│   ▼ Android MethodChannel / EventChannel                             │
│ Kotlin 原生层 (app/android/.../agy_go/)                              │
│   ├─ runtime/  AgyInstaller(SHA-512) + AgyProcess + AgyService       │
│   ├─ phone/    PhoneMcpServer(MCP HTTP) + SafetyGate + 无障碍服务     │
│   ├─ voice/    SpeechRecognizer + TextToSpeech                       │
│   ├─ pet/      PetOverlayService (SYSTEM_ALERT_WINDOW 靠边吸附)      │
│   └─ system/   FileProvider 分享/APK 安装 + 厂商省电豁免与自启动跳转  │
└──────────────────────────────────────────────────────────────────────┘
```

## 2. 本机运行环境（默认原生 Bionic + 可选 PRoot Linux）

- **默认模式（Android 原生 Bionic `arm64`）**：Google 官方自动更新器发布 `android_arm64` 原生 Bionic 二进制。配合 `minSdk = 26`、`targetSdk = 28`，`AgyInstaller.kt` 在首次启动时直接拉取、校验 SHA-512 并原子解压至 `filesDir/runtime/bin/agy`，冷启动快且免去 1GB 镜像门槛。
- **可选 PRoot Ubuntu 24.04 容器**：执行 `bash runtime/build-rootfs.sh arm64-v8a`（或 `x86_64`）生成 Ubuntu 24.04 rootfs 与 Termux `libproot.so` / `libtalloc.so` / `libandroid-shmem.so`，由 Gradle 自动打包并在 `EngineScreen` 解锁 PRoot 切换开关。
- **后台不断任务**：`AgyService` 前台服务持有 `agy acp` 子进程并通过随机 24 字节令牌鉴权的 `127.0.0.1` 回环桥接给 Flutter，Activity 重建或切后台不断流。

## 2B. 工作区与手机共享存储挂载（参考 DSH Go）

- **存储权限策略（`PhoneStorage.kt`）**：配合 `targetSdk = 28` 与 `android:requestLegacyExternalStorage="true"`，优先通过标准运行时存储权限（`READ/WRITE_EXTERNAL_STORAGE`）授权，并在 Android 11+ 受限时提供「所有文件访问（`MANAGE_EXTERNAL_STORAGE`）」设置直达。
- **双模式挂载与快捷入口**：
  - **原生 Bionic 模式**：进程直通访问 `/storage/emulated/0`，自动同步创建 `HOME/手机存储 -> /storage/emulated/0` 软链。
  - **PRoot 容器模式**：启动 `proot` 时注入 `-b /storage/emulated/0:/sdcard -b /storage` 及额外已注册工作区目录绑定，并在容器内创建 `/root/手机存储 -> /sdcard`。
- **托管工作区提示（`GuestWorkspaceSetup.kt`）**：在受控标记（`<!-- agy-go:managed`）保护下写入 `.gemini/GEMINI.md` 与 `AGENTS.md`，明确告知 `agy` 已挂载的手机存储路径与推荐输出目录 `/storage/emulated/0/Download/AGY-Go/`。
- **多工作区注册与 ACP `cwd` 绑定（`WorkspacesController` + `DirectoryBrowserPage`）**：按主机独立持久化多个工作区（置顶、分组、最近路径），抽屉和空状态随时切换；新建会话时将选中工作区的真实路径作为 `cwd` 传给 `agy acp` 的 `session/new`。

## 3. MCP 手机操控安全边界（SafetyGate）

- `PhoneMcpServer.kt` 在 `127.0.0.1:<随机端口>/mcp` 提供标准 MCP Streamable HTTP（JSON-RPC 2.0，Bearer Token 鉴权），由 `PhonePlugin` 自动写入 `~/.gemini/antigravity-cli/settings.json` 并在 `ChatController` 的 `session/new` 中通过 `HttpMcpServerConfig` 注入，完全无需改动 `agy` 二进制。
- `SafetyGate.kt` 强制执行三档确认策略，对银行/支付/密码管理器包名及敏感关键词（支付、转账、验证码、密码、卸载、删除等）的修改操作**始终拦截并等待人工确认**；超时、断连或点击「紧急停止」均 **fail-closed 拒绝**。

## 4. 语音、桌宠、分享与系统集成

- **语音（`VoicePlugin.kt`）**：调用 Android 原生 `SpeechRecognizer` 流式识别并回填至 `ComposerBar`，同时提供 `TextToSpeech` 回复朗读。
- **原创伴侣星灵（`StarlingAvatar` + `PetOverlayService.kt`）**：纯代码绘制动画，无任何第三方受限版权素材；状态由 `petMoodProvider` 实时联动（思考、工具执行、等待确认、完成、休眠）。
- **分享与回放（`ConversationExport` + `ShareScreen`）**：导出前自动正则脱敏 API Key / OAuth Token / 私钥 PEM，支持 `RepaintBoundary` 3x PNG 分享卡（经 `FileProvider` 调用系统分享）与 `agy-go-replay/v1` JSON 步进回放。
- **后台保活与自更新（`SystemPlugin.kt` + `KeepAliveAndUpdateScreen`）**：识别小米/华为/荣耀/OPPO/vivo/三星 ROM 并提供省电豁免及厂商自启动直达，支持检查 GitHub Releases 最新 APK 并验证下载安装。
