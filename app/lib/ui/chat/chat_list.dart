import 'package:acp_client/acp_client.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../runtime/runtime_models.dart';
import '../../state/chat_state.dart';
import '../../state/connection_state.dart';
import '../../state/hosts_state.dart';
import '../../state/runtime_state.dart';
import '../../state/voice_state.dart';
import '../engine/engine_screen.dart';
import '../remote/ssh_hosts_screen.dart';
import '../theme/app_theme.dart';
import '../theme/glass_widgets.dart';
import 'tool_call_card.dart';

class ChatList extends ConsumerStatefulWidget {
  const ChatList({super.key, required this.onPickSuggestion});

  final void Function(String prompt) onPickSuggestion;

  @override
  ConsumerState<ChatList> createState() => _ChatListState();
}

class _ChatListState extends ConsumerState<ChatList> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatProvider);
    final items = chat.transcript.items;

    if (chat.isLoadingSession) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    if (items.isEmpty) {
      return _EmptyChatView(onPickSuggestion: widget.onPickSuggestion);
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(14, 78, 14, 16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return Padding(
          key: ValueKey(item.id),
          padding: const EdgeInsets.only(bottom: 14),
          child: switch (item) {
            UserTranscriptItem() => _UserBubble(item: item),
            AssistantTranscriptItem() => _AssistantTurnView(item: item),
          },
        );
      },
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.item});

  final UserTranscriptItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(6),
            ),
          ),
          child: SelectableText(
            item.text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onPrimary,
              height: 1.45,
            ),
          ),
        ),
      ),
    );
  }
}

class _AssistantTurnView extends ConsumerStatefulWidget {
  const _AssistantTurnView({required this.item});

  final AssistantTranscriptItem item;

  @override
  ConsumerState<_AssistantTurnView> createState() => _AssistantTurnViewState();
}

class _AssistantTurnViewState extends ConsumerState<_AssistantTurnView> {
  bool _processExpanded = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final surfaces = AgySurfaces.of(context);
    final theme = Theme.of(context);
    final isSpeaking = ref.watch(voiceProvider.select((v) => v.isSpeaking));

    final showProcessExpanded =
        _processExpanded || (item.isStreaming && item.text.isEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (item.hasActivity) ...[
          InkWell(
            onTap: () => setState(() => _processExpanded = !_processExpanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (item.isStreaming)
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: theme.colorScheme.primary,
                      ),
                    )
                  else
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 14,
                      color: surfaces.subtleText,
                    ),
                  const SizedBox(width: 6),
                  Text(
                    _processSummary(item),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: surfaces.subtleText,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    showProcessExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 16,
                    color: surfaces.subtleText,
                  ),
                ],
              ),
            ),
          ),
          if (showProcessExpanded) ...[
            if (item.thought.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 8),
                child: HairlineCard(
                  padding: const EdgeInsets.all(11),
                  borderRadius: BorderRadius.circular(14),
                  child: Text(
                    item.thought,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: surfaces.subtleText,
                      height: 1.45,
                    ),
                  ),
                ),
              ),
            for (final tc in item.toolCalls)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: ToolCallCard(toolCall: tc),
              ),
          ],
          const SizedBox(height: 6),
        ],
        if (item.text.isNotEmpty) ...[
          HairlineCard(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(6),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(18),
            ),
            child: SelectionArea(
              child: GptMarkdown(
                item.text,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
              ),
            ),
          ),
          if (!item.isStreaming)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      isSpeaking
                          ? Icons.stop_circle_outlined
                          : Icons.volume_up_outlined,
                      size: 17,
                      color: surfaces.subtleText,
                    ),
                    tooltip: isSpeaking ? '停止朗读' : '语音朗读',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      final voice = ref.read(voiceProvider.notifier);
                      if (isSpeaking) {
                        voice.stopSpeaking();
                      } else {
                        voice.speak(item.text);
                      }
                    },
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.copy_rounded,
                      size: 16,
                      color: surfaces.subtleText,
                    ),
                    tooltip: '复制回复',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: item.text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制回复内容')),
                      );
                    },
                  ),
                ],
              ),
            ),
        ] else if (item.isStreaming && !item.hasActivity)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '思考中…',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: surfaces.subtleText,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _processSummary(AssistantTranscriptItem item) {
    final parts = <String>[];
    if (item.thought.isNotEmpty) parts.add('思考过程');
    if (item.toolCalls.isNotEmpty) {
      parts.add('${item.toolCalls.length} 次工具调用');
    }
    if (item.isStreaming) return '${parts.join(' · ')}（进行中）';
    return parts.join(' · ');
  }
}

class _EmptyChatView extends ConsumerWidget {
  const _EmptyChatView({required this.onPickSuggestion});

  final void Function(String prompt) onPickSuggestion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hosts = ref.watch(hostsProvider);
    final runtime = ref.watch(localRuntimeProvider);
    final connAsync = ref.watch(activeConnectionProvider);
    final surfaces = AgySurfaces.of(context);
    final theme = Theme.of(context);

    final connected = connAsync.value != null;
    final st = runtime.status;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 92, 22, 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.primary.withValues(alpha: 0.55),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.rocket_launch_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'AGY Go',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '在手机本机直接运行 Google Antigravity CLI，或一键切换 SSH 远程开发主机。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: surfaces.subtleText,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 22),

              if (!connected && hosts.active.isLocal) ...[
                HairlineCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.smartphone_rounded,
                            color: theme.colorScheme.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            st.phase == RuntimePhase.notInstalled
                                ? '安装手机本机 Antigravity CLI'
                                : st.phase == RuntimePhase.installing
                                ? '正在安装本机引擎…'
                                : '启动本机 Antigravity CLI',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        st.phase == RuntimePhase.notInstalled
                            ? '免 Root、免 Termux：直接下载 Google 官方 Android 原生 arm64 二进制并校验 SHA-512，首次约需几十秒。'
                            : st.phase == RuntimePhase.installing
                            ? (runtime.progress?.detail ?? '准备下载…')
                            : '已安装版本 ${st.installedVersion ?? 'unknown'}（${st.executionMode}），点击即可在后台前台服务中拉起 ACP 引擎。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: surfaces.subtleText,
                          height: 1.45,
                        ),
                      ),
                      if (st.phase == RuntimePhase.installing &&
                          runtime.progress != null) ...[
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value: runtime.progress!.fraction.clamp(0.0, 1.0),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ],
                      if (st.error != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          st.error!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: surfaces.danger,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: st.phase.isBusy
                                  ? null
                                  : () {
                                      if (st.phase == RuntimePhase.notInstalled ||
                                          (st.phase == RuntimePhase.error &&
                                              st.installedVersion == null)) {
                                        ref
                                            .read(localRuntimeProvider.notifier)
                                            .installOrUpdate();
                                      } else {
                                        ref
                                            .read(localRuntimeProvider.notifier)
                                            .start();
                                      }
                                    },
                              icon: Icon(
                                st.phase == RuntimePhase.notInstalled
                                    ? Icons.download_rounded
                                    : Icons.play_arrow_rounded,
                              ),
                              label: Text(
                                st.phase == RuntimePhase.notInstalled
                                    ? '一键安装本机引擎'
                                    : st.phase == RuntimePhase.installing
                                    ? '安装中…'
                                    : '启动本机引擎',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const EngineScreen(),
                              ),
                            ),
                            child: const Text('管理 / 登录'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SshHostsScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.dns_outlined, size: 18),
                  label: const Text('或配置 SSH 连接电脑 / 服务器上的 agy'),
                ),
              ] else if (connected) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final suggestion in const [
                      '检查当前工作区目录结构',
                      '写一个 Python 脚本并帮我运行测试',
                      '解释 git status 并总结最近改动',
                    ])
                      HairlineCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 9,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => onPickSuggestion(suggestion),
                        child: Text(
                          suggestion,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ] else if (connAsync.isLoading) ...[
                const CircularProgressIndicator.adaptive(),
                const SizedBox(height: 10),
                Text(
                  '正在连接 ${hosts.activeLabel()}…',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: surfaces.subtleText,
                  ),
                ),
              ] else if (connAsync.hasError) ...[
                HairlineCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(
                        '连接失败：${connAsync.error}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: surfaces.danger,
                        ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.tonal(
                        onPressed: () => ref
                            .read(activeConnectionProvider.notifier)
                            .reconnect(),
                        child: const Text('重试连接'),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
