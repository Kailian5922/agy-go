# AGY Go 架构设计

## 1. 总体分层

```text
┌─────────────────── Android App (Flutter + Kotlin) ───────────────────┐
│ Flutter UI (app/lib/ui/)                                             │
│   ├─ theme/    雾面玻璃、0.75px 细线、6 套主题色、边到边透明系统栏       │
│   ├─ shell/    三栏连续跟手手势外壳（SessionsDrawer / Chat / QuickPanel）│
│   ├─ chat/     流式 Markdown、思考/工具折叠、Diff 预览、权限审批卡       │
│   ├─ engine/   本机引擎一键安装/启停/更新/OAuth/API Key/脱敏日志        │
│   └─ remote/   SSH 主机管理 + xterm 交互终端                          │
│        │ Riverpod 3 (app/lib/state/)                                 │
│        ▼                                                             │
│ packages/acp_client  (纯 Dart ACP JSON-RPC 2.0 + ChatTranscript)      │
│        │ Pluggable AcpTransport (NDJSON)                             │
│   ┌────┴─────────────────────────┐                                   │
│   ▼                              ▼                                   │
│ LoopbackAcpTransport       SshAcpConnection (packages/agy_remote)    │
│ (127.0.0.1 + 随机 Token)    (dartssh2 exec `agy acp` + 指纹钉死)      │
│   │                                                                  │
│   ▼ Android MethodChannel/EventChannel (`agy/runtime`)               │
│ Kotlin RuntimeController + AgyService (ForegroundService)            │
│   ├─ AgyInstaller  官方 manifest 拉取 + SHA-512 校验 + 原子解压        │
│   ├─ AgyProcess    原生 Android Bionic `agy acp` / 可选 PRoot Linux   │
│   └─ AgyAuthHelper 管理 ~/.gemini/antigravity-cli/settings.json       │
└──────────────────────────────────────────────────────────────────────┘
```

## 2. 为什么 Android 本机可以直接跑官方 `agy`

Google 官方 `antigravity-cli` 自动更新器为 `arm64-v8a` 发布了原生 Android Bionic 版本：
- 清单地址：`https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/android_arm64.json`
- 配合 `minSdk = 26`、`targetSdk = 28`（避开 Android 10+ 对应用私有目录 `exec()` 的 W^X 限制），`AgyInstaller.kt` 可直接在首次使用时下载、校验 SHA-512 并解压至 `filesDir/runtime/bin/agy`，冷启动极快且免去了 1GB PRoot 镜像的前置门槛。
- 当需要完整 Ubuntu 工具链（`apt`、`git`、`python3`、`node`）或在 `x86_64` 模拟器上运行时，可按 `runtime/README.md` 启用可选的 PRoot Ubuntu 24.04 容器模式。

## 3. 切后台不断任务的设计

`agy acp` 的标准协议跑在 stdin/stdout 上。如果由 Dart 进程直接持有子进程，Android Activity 重建或系统回收 Flutter 视图时容易中断管道。

AGY Go 采用 **ForegroundService + 本地令牌回环桥（`AgyProcess.kt`）**：
1. `AgyService` 作为前台服务保活，持有 `agy acp` 子进程。
2. 每次启动监听 `127.0.0.1:<随机端口>` 并生成 24 字节 `SecureRandom` 会话令牌。
3. Flutter 连接后首行校验 `{"auth":"<token>"}\n`，校验通过后透明转发双向 NDJSON 帧；Flutter 断开重连时子进程保持存活。

## 4. 后续 Phase 3 / Phase 4 扩展接口

- **Phase 3（MCP 手机操控）**：`AcpClient.newSession()` 已完整支持 `mcpServers` 参数（`StdioMcpServerConfig` / `HttpMcpServerConfig`），后续只需在 Kotlin 侧实现本地 MCP Server（无障碍 + Shizuku + `SafetyGate`）即可直接挂载给 `agy`，无需改动任何引擎二进制。
- **Phase 4（体验增强）**：语音 VAD、悬浮桌宠、加密分享回放与自更新均围绕 `app/lib/state/` 独立模块扩展，不侵入 `packages/acp_client`。
