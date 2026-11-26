// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.
// Native Antigravity CLI (`agy`) extensions management: MCP servers, Skills, GEMINI.md rules, and settings.json.

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/agy_config_state.dart';
import '../../state/phone_state.dart';
import '../../state/settings_state.dart';
import '../chat/diff_and_output_page.dart';
import '../common/app_dialog.dart';
import '../common/app_sheet.dart';
import '../common/brief_notice.dart';
import '../common/empty_view.dart';
import '../common/list_page_row.dart';
import '../common/settings_widgets.dart';
import '../common/status_chip.dart';
import '../phone/phone_control_screen.dart';
import '../shell/page_frame.dart';
import '../theme/theme.dart';
import '../workspace/workspaces_ui.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 1. MCP Servers Management Page (/mcp)
// ─────────────────────────────────────────────────────────────────────────────

class McpServersPage extends ConsumerWidget {
  const McpServersPage({super.key});

  Future<void> _showEditSheet(
    BuildContext context,
    WidgetRef ref, {
    AgyMcpServerEntry? initial,
  }) async {
    final nameCtrl = TextEditingController(text: initial?.name ?? '');
    final cmdCtrl = TextEditingController(text: initial?.command ?? '');
    final argsCtrl = TextEditingController(
      text: initial?.args.join(' ') ?? '',
    );
    final urlCtrl = TextEditingController(text: initial?.url ?? '');
    var transport = initial?.transport ?? 'http';
    var enabled = initial?.enabled ?? true;

    final saved = await showAppSheet<AgyMcpServerEntry>(
      context,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheet).bottom,
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SheetHeader(initial == null ? '添加 MCP 服务器' : '编辑 MCP 服务器'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: nameCtrl,
                          enabled: initial == null,
                          decoration: const InputDecoration(
                            labelText: '名称（唯一标识）',
                            hintText: '例如 github / filesystem / context7',
                          ),
                        ),
                        const SizedBox(height: 12),
                        SegmentedPill<String>(
                          selected: transport,
                          onChanged: (v) => setState(() => transport = v),
                          segments: const [
                            PillSegment('http', 'HTTP'),
                            PillSegment('sse', 'SSE'),
                            PillSegment('stdio', 'Stdio'),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (transport == 'stdio') ...[
                          TextField(
                            controller: cmdCtrl,
                            style: AppType.mono(size: 13.5),
                            decoration: const InputDecoration(
                              labelText: '启动命令',
                              hintText: '例如 npx 或 /usr/bin/python3',
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: argsCtrl,
                            style: AppType.mono(size: 13.5),
                            decoration: const InputDecoration(
                              labelText: '参数（空格分隔）',
                              hintText: '例如 -y @modelcontextprotocol/server-github',
                            ),
                          ),
                        ] else ...[
                          TextField(
                            controller: urlCtrl,
                            style: AppType.mono(size: 13.5),
                            decoration: const InputDecoration(
                              labelText: '服务器 URL',
                              hintText: 'https://example.com/mcp',
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('启用此服务器'),
                          value: enabled,
                          onChanged: (v) => setState(() => enabled = v),
                        ),
                        const SizedBox(height: 10),
                        FilledButton(
                          onPressed: () {
                            final name = nameCtrl.text.trim();
                            if (name.isEmpty) {
                              showBriefNotice(sheet, '请输入服务器名称');
                              return;
                            }
                            if (transport == 'stdio' &&
                                cmdCtrl.text.trim().isEmpty) {
                              showBriefNotice(sheet, '请输入启动命令');
                              return;
                            }
                            if (transport != 'stdio' &&
                                urlCtrl.text.trim().isEmpty) {
                              showBriefNotice(sheet, '请输入服务器 URL');
                              return;
                            }
                            Navigator.of(sheet).pop(
                              AgyMcpServerEntry(
                                name: name,
                                transport: transport,
                                command: cmdCtrl.text.trim(),
                                args: argsCtrl.text
                                    .trim()
                                    .split(RegExp(r'\s+'))
                                    .where((s) => s.isNotEmpty)
                                    .toList(),
                                url: urlCtrl.text.trim(),
                                headers: initial?.headers ?? const {},
                                env: initial?.env ?? const {},
                                enabled: enabled,
                              ),
                            );
                          },
                          child: const Text('写入 settings.json'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    nameCtrl.dispose();
    cmdCtrl.dispose();
    argsCtrl.dispose();
    urlCtrl.dispose();

    if (saved != null) {
      await ref.read(agyConfigProvider.notifier).upsertMcpServer(saved);
      if (context.mounted) {
        showBriefNotice(context, '已保存 MCP「${saved.name}」，新建对话后自动注入');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(agyConfigProvider);
    final phone = ref.watch(phoneControlProvider);

    return AppPage.list(
      title: 'MCP 服务管理',
      subtitle: const Text('配置 ~/.gemini/antigravity-cli/settings.json 中的 MCP 扩展'),
      actions: [
        GlassIconButton(
          icon: AppIcons.refresh,
          tooltip: '重新读取',
          onPressed: () =>
              unawaited(ref.read(agyConfigProvider.notifier).refresh()),
        ),
        GlassIconButton(
          icon: AppIcons.add,
          tooltip: '添加 MCP',
          onPressed: () => unawaited(_showEditSheet(context, ref)),
        ),
      ],
      children: [
        SettingsSection(
          title: '内置本机服务',
          children: [
            SettingsTile(
              icon: AppIcons.phoneControl,
              tint: 3,
              title: 'phone（手机操控 MCP）',
              subtitle: phone.isMcpReady
                  ? (phone.mcpUrl ?? '已就绪')
                  : '启用无障碍后自动向本机 agy 注入手机操控工具',
              value: StatusChip(
                tone: phone.isMcpReady
                    ? StatusTone.ok
                    : phone.enabled
                    ? StatusTone.warn
                    : StatusTone.idle,
                label: phone.isMcpReady
                    ? '已注入'
                    : phone.enabled
                    ? '待无障碍'
                    : '未开启',
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PhoneControlScreen(),
                ),
              ),
            ),
          ],
        ),
        if (config.mcpServers.isEmpty)
          EmptyView(
            icon: AppIcons.plugin,
            title: '还没有自定义 MCP 服务器',
            message: '可添加 HTTP / SSE / Stdio MCP 服务器，保存后同步写入 Antigravity CLI 配置并在新会话中自动加载。',
            actionLabel: '添加 MCP 服务器',
            onAction: () => unawaited(_showEditSheet(context, ref)),
          )
        else
          ListPageCard(
            title: '用户配置 (${config.mcpServers.length})',
            children: [
              for (final entry in config.mcpServers)
                ListPageRow(
                  icon: entry.isRemote ? AppIcons.web : AppIcons.terminal,
                  title: entry.name,
                  titleNote: entry.transport.toUpperCase(),
                  subtitle: entry.isRemote
                      ? entry.url
                      : '${entry.command} ${entry.args.join(' ')}'.trim(),
                  trailing: Switch.adaptive(
                    value: entry.enabled,
                    onChanged: (v) => unawaited(
                      ref
                          .read(agyConfigProvider.notifier)
                          .upsertMcpServer(entry.copyWith(enabled: v)),
                    ),
                  ),
                  onTap: () =>
                      unawaited(_showEditSheet(context, ref, initial: entry)),
                  onLongPress: () async {
                    final ok = await showAppDialog<bool>(
                      context: context,
                      builder: (d) => AlertDialog(
                        title: Text('删除 MCP「${entry.name}」？'),
                        content: const Text('将从 settings.json 中移除此项配置。'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(d).pop(false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(d).pop(true),
                            child: const Text('删除'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await ref
                          .read(agyConfigProvider.notifier)
                          .deleteMcpServer(entry.name);
                      if (context.mounted) {
                        showBriefNotice(context, '已删除 ${entry.name}');
                      }
                    }
                  },
                ),
            ],
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. Skills & Memory Rules Page (/skills, /memory, /rules)
// ─────────────────────────────────────────────────────────────────────────────

class SkillsAndRulesPage extends ConsumerStatefulWidget {
  const SkillsAndRulesPage({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  ConsumerState<SkillsAndRulesPage> createState() => _SkillsAndRulesPageState();
}

class _SkillsAndRulesPageState extends ConsumerState<SkillsAndRulesPage> {
  late int _tab = widget.initialTab;

  Future<void> _openCreateSkillSheet() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final bodyCtrl = TextEditingController(
      text: '## 使用说明\n\n当用户调用本技能时，请按以下步骤执行：\n1. \n2. ',
    );
    var global = true;

    final created = await showAppSheet<bool>(
      context,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheet).bottom,
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SheetHeader('新建 Agent Skill'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SegmentedPill<bool>(
                          selected: global,
                          onChanged: (v) => setState(() => global = v),
                          segments: const [
                            PillSegment(true, '全局 (~/.gemini/skills)'),
                            PillSegment(false, '当前工作区 (.agents/skills)'),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: nameCtrl,
                          style: AppType.mono(size: 13.5),
                          decoration: const InputDecoration(
                            labelText: 'Skill 名称（英文/短横线）',
                            hintText: '例如 code-review 或 daily-brief',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: descCtrl,
                          decoration: const InputDecoration(
                            labelText: '简要说明',
                            hintText: '一句话描述这个技能的用途与触发时机',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: bodyCtrl,
                          minLines: 4,
                          maxLines: 8,
                          style: AppType.mono(size: 12.5),
                          decoration: const InputDecoration(
                            labelText: 'SKILL.md 指令正文',
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () async {
                            if (nameCtrl.text.trim().isEmpty) {
                              showBriefNotice(sheet, '请输入 Skill 名称');
                              return;
                            }
                            await ref.read(agyConfigProvider.notifier).createSkill(
                              name: nameCtrl.text,
                              description: descCtrl.text.isEmpty
                                  ? '自定义 Antigravity 技能'
                                  : descCtrl.text,
                              body: bodyCtrl.text,
                              global: global,
                            );
                            if (sheet.mounted) Navigator.of(sheet).pop(true);
                          },
                          child: const Text('创建并注册到 / 面板'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    nameCtrl.dispose();
    descCtrl.dispose();
    bodyCtrl.dispose();
    if (created == true && mounted) {
      showBriefNotice(context, '已创建 Skill，输入 / 即可快速调用');
    }
  }

  Future<void> _openMemoryEditor({
    required bool global,
    required String title,
    required String path,
    required String initialText,
  }) async {
    final ctrl = TextEditingController(text: initialText);
    final saved = await showAppSheet<String>(
      context,
      isScrollControlled: true,
      builder: (sheet) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheet).bottom),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SheetHeader(title),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        path,
                        style: AppType.monoLabel(
                          color: DshColors.of(sheet).textTertiary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: ctrl,
                        minLines: 8,
                        maxLines: 16,
                        style: AppType.mono(size: 13),
                        decoration: const InputDecoration(
                          hintText: '写入长期编码约定、项目规范或回答偏好（Markdown 格式）…',
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => Navigator.of(sheet).pop(ctrl.text),
                        child: const Text('保存 GEMINI.md'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    ctrl.dispose();
    if (saved != null) {
      await ref
          .read(agyConfigProvider.notifier)
          .saveMemoryFile(global: global, content: saved);
      if (mounted) showBriefNotice(context, '已保存 $title');
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(agyConfigProvider);

    return AppPage.list(
      title: 'Skills 与记忆规则',
      subtitle: const Text('管理 Antigravity Agent Skills 与 GEMINI.md 长期记忆'),
      actions: [
        GlassIconButton(
          icon: AppIcons.refresh,
          tooltip: '重新扫描',
          onPressed: () =>
              unawaited(ref.read(agyConfigProvider.notifier).refresh()),
        ),
        if (_tab == 0)
          GlassIconButton(
            icon: AppIcons.add,
            tooltip: '新建 Skill',
            onPressed: () => unawaited(_openCreateSkillSheet()),
          ),
      ],
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          child: SegmentedPill<int>(
            selected: _tab,
            onChanged: (v) => setState(() => _tab = v),
            segments: [
              PillSegment(0, 'Skills (${config.skills.length})'),
              const PillSegment(1, '记忆与规则 (GEMINI.md)'),
            ],
          ),
        ),
        if (_tab == 0) ...[
          if (config.skills.isEmpty)
            EmptyView(
              icon: AppIcons.skill,
              title: '未发现已安装的 Skill',
              message:
                  '将 SKILL.md 放在 ~/.gemini/skills/<名称>/ 或工作区 .agents/skills/<名称>/ 下即可自动发现，并出现在聊天 / 面板中。',
              actionLabel: '新建第一个 Skill',
              onAction: () => unawaited(_openCreateSkillSheet()),
            )
          else
            ListPageCard(
              title: '已扫描的 Agent Skills',
              children: [
                for (final skill in config.skills)
                  ListPageRow(
                    icon: AppIcons.skill,
                    title: '/${skill.name}',
                    titleNote: skill.scope == 'workspace' ? '工作区' : '全局',
                    subtitle: skill.description,
                    subtitleMaxLines: 2,
                    onTap: () async {
                      String body = '';
                      try {
                        body = await File(skill.filePath).readAsString();
                      } catch (_) {
                        body = '无法读取 ${skill.filePath}';
                      }
                      if (!context.mounted) return;
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => OutputViewerPage(
                            title: 'Skill: /${skill.name}',
                            subtitle: skill.filePath,
                            output: body,
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
        ] else ...[
          SettingsSection(
            title: '全局记忆 (~/.gemini/GEMINI.md)',
            footer: const Text(
              '全局规则对所有工作区与对话生效，适合写个人回复语言偏好、通用代码风格与安全红线。',
            ),
            children: [
              SettingsTile(
                icon: AppIcons.document,
                tint: 0,
                title: '编辑全局 GEMINI.md',
                subtitle: config.globalMemoryText.trim().isEmpty
                    ? '尚未编写（点击创建）'
                    : '${config.globalMemoryText.trim().split('\n').length} 行 · 点击查看与修改',
                onTap: () => unawaited(
                  _openMemoryEditor(
                    global: true,
                    title: '全局 GEMINI.md',
                    path: config.globalMemoryPath,
                    initialText: config.globalMemoryText,
                  ),
                ),
              ),
            ],
          ),
          SettingsSection(
            title: '当前工作区记忆 (<workspace>/GEMINI.md)',
            footer: const Text(
              '工作区规则仅在当前项目目录生效，适合记录构建命令、目录结构与项目架构约定。',
            ),
            children: [
              SettingsTile(
                icon: AppIcons.workspace,
                tint: 4,
                title: '编辑工作区 GEMINI.md',
                subtitle: config.workspaceMemoryText.trim().isEmpty
                    ? '当前工作区尚未创建 GEMINI.md'
                    : '${config.workspaceMemoryText.trim().split('\n').length} 行 · ${config.workspaceMemoryPath}',
                onTap: () => unawaited(
                  _openMemoryEditor(
                    global: false,
                    title: '工作区 GEMINI.md',
                    path: config.workspaceMemoryPath,
                    initialText: config.workspaceMemoryText,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. Antigravity Engine Parameters & settings.json Page (/config)
// ─────────────────────────────────────────────────────────────────────────────

class AgyEngineParamsPage extends ConsumerStatefulWidget {
  const AgyEngineParamsPage({super.key});

  @override
  ConsumerState<AgyEngineParamsPage> createState() =>
      _AgyEngineParamsPageState();
}

class _AgyEngineParamsPageState extends ConsumerState<AgyEngineParamsPage> {
  int _tab = 0;
  final _rawCtrl = TextEditingController();
  bool _rawSynced = false;

  static const _rulePresets = <(String, String, String)>[
    ('allow', 'command(git)', '放行只读/常规 git 命令'),
    ('allow', 'command(flutter test)', '放行 flutter test 测试'),
    ('ask', 'command(rm)', '删除命令总是先询问'),
    ('deny', 'write_file(.git/)', '禁止直接改写 .git/ 目录'),
    ('deny', 'read_file(.env)', '禁止读取 .env 密钥文件'),
  ];

  @override
  void dispose() {
    _rawCtrl.dispose();
    super.dispose();
  }

  Future<void> _addRuleDialog(String listName, String label) async {
    final rule = await showTextPromptDialog(
      context,
      title: '添加 $label 规则',
      caption: '官方语法：action(target)，例如 command(git)、write_file(src/)、read_url(docs.flutter.dev)、mcp(github/*)',
      hint: 'command(git)',
      mono: true,
      confirmLabel: '添加',
    );
    if (rule == null || rule.trim().isEmpty) return;
    await ref
        .read(agyConfigProvider.notifier)
        .addPermissionRule(listName, rule.trim());
    if (mounted) showBriefNotice(context, '已添加到 permissions.$listName');
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final config = ref.watch(agyConfigProvider);
    final dsh = DshColors.of(context);

    if (!_rawSynced && config.loaded) {
      _rawCtrl.text = config.rawSettingsJson;
      _rawSynced = true;
    }

    return AppPage.list(
      title: '引擎参数与规则',
      subtitle: const Text('可视化配置或直接编辑 ~/.gemini/antigravity-cli/settings.json'),
      actions: [
        GlassIconButton(
          icon: AppIcons.refresh,
          tooltip: '重新读取',
          onPressed: () async {
            await ref.read(agyConfigProvider.notifier).refresh();
            if (context.mounted) {
              _rawCtrl.text = ref.read(agyConfigProvider).rawSettingsJson;
              showBriefNotice(context, '已重新加载 settings.json');
            }
          },
        ),
      ],
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          child: SegmentedPill<int>(
            selected: _tab,
            onChanged: (v) {
              setState(() => _tab = v);
              if (v == 1) {
                _rawCtrl.text = ref.read(agyConfigProvider).rawSettingsJson;
              }
            },
            segments: const [
              PillSegment(0, '可视化与权限规则'),
              PillSegment(1, '原始 settings.json'),
            ],
          ),
        ),
        if (_tab == 0) ...[
          SettingsSection(
            title: '核心行为参数',
            children: [
              SettingsSegmentTile<AgyArtifactReviewPolicy>(
                icon: AppIcons.plan,
                tint: 0,
                title: '计划产物审核策略',
                segments: const [
                  PillSegment(AgyArtifactReviewPolicy.asksForReview, '等待审核'),
                  PillSegment(AgyArtifactReviewPolicy.alwaysProceed, '自动继续'),
                ],
                selected: settings.artifactReviewPolicy,
                onChanged: (v) => unawaited(notifier.setArtifactReviewPolicy(v)),
              ),
              SettingsSegmentTile<AgyQueuedMessageBehavior>(
                icon: AppIcons.queued,
                tint: 4,
                title: '生成中再发消息的行为',
                segments: const [
                  PillSegment(AgyQueuedMessageBehavior.queue, '排队等本轮完'),
                  PillSegment(AgyQueuedMessageBehavior.steer, '立即插话引导'),
                ],
                selected: settings.queuedBehavior,
                onChanged: (v) => unawaited(notifier.setQueuedBehavior(v)),
              ),
              SettingsSwitchTile(
                icon: AppIcons.folderOpen,
                tint: 5,
                title: '允许访问工作区外目录',
                subtitle: '对应 allowNonWorkspaceAccess，支持读取已挂载手机存储与额外目录',
                value: settings.allowNonWorkspaceAccess,
                onChanged: (v) =>
                    unawaited(notifier.setAllowNonWorkspaceAccess(v)),
              ),
            ],
          ),
          _RuleSection(
            title: '自动放行 (permissions.allow)',
            rules: config.permissionRules.allow,
            icon: AppIcons.allowed,
            iconColor: dsh.success,
            onAdd: () => unawaited(_addRuleDialog('allow', 'allow 放行')),
            onRemove: (r) => unawaited(
              ref
                  .read(agyConfigProvider.notifier)
                  .removePermissionRule('allow', r),
            ),
          ),
          _RuleSection(
            title: '始终询问 (permissions.ask)',
            rules: config.permissionRules.ask,
            icon: AppIcons.question,
            iconColor: dsh.warning,
            onAdd: () => unawaited(_addRuleDialog('ask', 'ask 询问')),
            onRemove: (r) => unawaited(
              ref
                  .read(agyConfigProvider.notifier)
                  .removePermissionRule('ask', r),
            ),
          ),
          _RuleSection(
            title: '强制禁止 (permissions.deny)',
            rules: config.permissionRules.deny,
            icon: AppIcons.blocked,
            iconColor: dsh.danger,
            onAdd: () => unawaited(_addRuleDialog('deny', 'deny 禁止')),
            onRemove: (r) => unawaited(
              ref
                  .read(agyConfigProvider.notifier)
                  .removePermissionRule('deny', r),
            ),
          ),
          ListPageCard(
            title: '一键添加常用官方规则模板',
            children: [
              for (final (bucket, rule, desc) in _rulePresets)
                ListPageRow(
                  icon: AppIcons.addEntry,
                  title: rule,
                  titleNote: bucket,
                  subtitle: desc,
                  chevron: false,
                  onTap: () async {
                    await ref
                        .read(agyConfigProvider.notifier)
                        .addPermissionRule(bucket, rule);
                    if (context.mounted) {
                      showBriefNotice(context, '已添加 $bucket: $rule');
                    }
                  },
                ),
            ],
          ),
        ] else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(
              config.settingsPath,
              style: AppType.monoLabel(color: dsh.textTertiary),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GlassSurface(
              tier: GlassTier.card,
              borderRadius: AppShape.radiusLg,
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _rawCtrl,
                minLines: 14,
                maxLines: 28,
                style: AppType.monoSmall(
                  color: Theme.of(context).colorScheme.onSurface,
                ).copyWith(fontSize: 12.5, height: 1.5),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: FilledButton.icon(
              icon: const Icon(AppIcons.done, size: 18),
              label: const Text('校验并保存 settings.json'),
              onPressed: () async {
                final err = await ref
                    .read(agyConfigProvider.notifier)
                    .saveRawSettingsJson(_rawCtrl.text);
                if (!context.mounted) return;
                if (err != null) {
                  showBriefNotice(context, err);
                } else {
                  showBriefNotice(context, 'settings.json 已校验保存');
                }
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _RuleSection extends StatelessWidget {
  const _RuleSection({
    required this.title,
    required this.rules,
    required this.icon,
    required this.iconColor,
    required this.onAdd,
    required this.onRemove,
  });

  final String title;
  final List<String> rules;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return ListPageCard(
      title: title,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      children: [
        for (final rule in rules)
          ListPageRow(
            icon: icon,
            iconColor: iconColor,
            title: rule,
            titleStyle: AppType.mono(size: 13.5),
            trailing: IconButton(
              icon: const Icon(AppIcons.delete, size: 18),
              tooltip: '移除规则',
              onPressed: () => onRemove(rule),
            ),
            chevron: false,
          ),
        ListPageRow(
          icon: AppIcons.add,
          title: '添加规则',
          chevron: false,
          onTap: onAdd,
        ),
      ],
    );
  }
}
