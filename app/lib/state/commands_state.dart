// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.
// Tailored natively for Google Antigravity CLI (`agy` / `agy acp`) commands & skills.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../ui/theme/app_icons.dart';
import 'agy_config_state.dart';
import 'chat_state.dart';

enum SlashCommandKind {
  /// Executed directly by AGY Go UI (opens native sheet/page or calls ACP RPC).
  app,

  /// Native Antigravity CLI (`agy`) command sent in the conversation prompt.
  agy,

  /// Discovered Agent Skill (`SKILL.md`); inserted as `/skill-name ` for prompting.
  skill,
}

class SlashCommand {
  const SlashCommand({
    required this.name,
    required this.label,
    required this.description,
    required this.icon,
    this.aliases = const [],
    this.hint,
    this.kind = SlashCommandKind.app,
  });

  final String name;
  final String label;
  final String description;
  final IconData icon;
  final List<String> aliases;

  /// Non-null when the command accepts arguments (shows `PaletteHint` after space).
  final String? hint;
  final SlashCommandKind kind;

  bool get takesInput => hint != null;
}

/// Complete AGY Go + Antigravity CLI (`agy`) slash command catalog.
const List<SlashCommand> builtInAgySlashCommands = <SlashCommand>[
  // ── Core App & Control Panels ───────────────────────────────────────────────
  SlashCommand(
    name: 'new',
    label: '新对话',
    aliases: ['clear', '新对话', '清空'],
    description: '清空当前界面并开始全新对话',
    icon: AppIcons.newChat,
    kind: SlashCommandKind.app,
  ),
  SlashCommand(
    name: 'permissions',
    label: '审批与权限',
    aliases: ['permission', 'perm', '权限', '审批'],
    description: '切换执行模式（标准/自动改写/计划/YOLO）与工具权限规则',
    icon: AppIcons.permissions,
    kind: SlashCommandKind.app,
  ),
  SlashCommand(
    name: 'mode',
    label: '执行模式',
    aliases: ['模式'],
    description: '快速切换 default / accept-edits / auto / plan',
    icon: AppIcons.modes,
    kind: SlashCommandKind.app,
  ),
  SlashCommand(
    name: 'model',
    label: '切换模型',
    aliases: ['模型'],
    description: '选择当前会话模型与认证通道',
    icon: AppIcons.providers,
    kind: SlashCommandKind.app,
  ),
  SlashCommand(
    name: 'effort',
    label: '思考深度',
    aliases: ['thinking', '思考'],
    description: '切换模型推理力度（Low / Medium / High / Extra / Max）',
    icon: AppIcons.askAi,
    kind: SlashCommandKind.app,
  ),
  // ── Native Antigravity CLI (`agy`) Agent Workflows ──────────────────────────
  SlashCommand(
    name: 'plan',
    label: '计划模式',
    aliases: ['计划', '规划'],
    description: '先调研代码并输出可审核的实施方案，再动手修改',
    hint: '[任务说明，留空则直接切换为计划模式]',
    icon: AppIcons.goal,
    kind: SlashCommandKind.agy,
  ),
  SlashCommand(
    name: 'compact',
    label: '压缩上下文',
    aliases: ['压缩'],
    description: '总结当前对话释放上下文窗口，可附带后续指令',
    hint: '[可选：压缩后继续执行的说明]',
    icon: AppIcons.compact,
    kind: SlashCommandKind.agy,
  ),
  SlashCommand(
    name: 'goal',
    label: '目标闭环',
    aliases: ['目标'],
    description: '自主持续推进直到验收通过（agy 原生 /goal）',
    hint: '<明确目标与验收标准>',
    icon: AppIcons.goal,
    kind: SlashCommandKind.agy,
  ),
  SlashCommand(
    name: 'grill-me',
    label: '设计访谈',
    aliases: ['grill', '访谈'],
    description: '开工前逐题提问澄清需求，每题附推荐选项',
    hint: '[想一起推敲的方案或任务]',
    icon: AppIcons.chat,
    kind: SlashCommandKind.agy,
  ),
  SlashCommand(
    name: 'boost',
    label: '深度推理',
    aliases: ['深度'],
    description: '按需开启多步深度推理循环（agy 原生 /boost）',
    hint: '<需要深入攻克的难题>',
    icon: AppIcons.edgeGlow,
    kind: SlashCommandKind.agy,
  ),
  SlashCommand(
    name: 'btw',
    label: '旁路提问',
    aliases: ['顺便问'],
    description: '不打断主线上下文，顺便问一个旁路问题',
    hint: '<简短问题>',
    icon: AppIcons.tip,
    kind: SlashCommandKind.agy,
  ),
  SlashCommand(
    name: 'learn',
    label: '沉淀规则',
    aliases: ['学习', '规则'],
    description: '将本轮纠错整理为持久的 GEMINI.md 规则或 Skill 草案',
    hint: '[可选：要记住的习惯或约束]',
    icon: AppIcons.bookmark,
    kind: SlashCommandKind.agy,
  ),
  SlashCommand(
    name: 'swarm',
    label: '多智能体蜂群',
    aliases: ['蜂群'],
    description: '启动多名协同 Worker 与验证者并行攻坚（agy 原生 /swarm）',
    hint: '<并行拆解的任务>',
    icon: AppIcons.subagents,
    kind: SlashCommandKind.agy,
  ),
  SlashCommand(
    name: 'teamwork',
    label: '智能体团队',
    aliases: ['团队'],
    description: '长周期多智能体协作编排（agy 原生 /teamwork）',
    hint: '<复杂项目目标>',
    icon: AppIcons.team,
    kind: SlashCommandKind.agy,
  ),
  SlashCommand(
    name: 'schedule',
    label: '定时任务',
    aliases: ['定时'],
    description: '设定单次或周期 Cron 唤醒指令（agy 原生 /schedule）',
    hint: '<时间/cron> <任务内容>',
    icon: AppIcons.automation,
    kind: SlashCommandKind.agy,
  ),
  SlashCommand(
    name: 'antigravity-guide',
    label: '官方指南问答',
    aliases: ['guide', 'help', '帮助'],
    description: '向 Antigravity 官方文档查询用法与配置',
    hint: '[想查的 agy 用法或配置]',
    icon: AppIcons.info,
    kind: SlashCommandKind.agy,
  ),
  // ── Workspace, Diff, Usage & Extension Panels ───────────────────────────────
  SlashCommand(
    name: 'workspace',
    label: '切换工作区',
    aliases: ['工作区'],
    description: '切换或挂载本机目录、手机存储与下载目录',
    icon: AppIcons.workspace,
    kind: SlashCommandKind.app,
  ),
  SlashCommand(
    name: 'add-dir',
    label: '挂载额外目录',
    aliases: ['挂载'],
    description: '选择额外目录（如 Download）作为本会话的 additionalDirectories',
    icon: AppIcons.newFolder,
    kind: SlashCommandKind.app,
  ),
  SlashCommand(
    name: 'diff',
    label: '查看变更 Diff',
    aliases: ['变更'],
    description: '全屏查看当前对话产生的所有文件修改对比',
    icon: AppIcons.code,
    kind: SlashCommandKind.app,
  ),
  SlashCommand(
    name: 'context',
    label: '上下文与用量',
    aliases: ['usage', 'quota', '用量', '上下文'],
    description: '查看 Token 占用进度条与费用，支持一键压缩',
    icon: AppIcons.diagnostics,
    kind: SlashCommandKind.app,
  ),
  SlashCommand(
    name: 'resume',
    label: '切换历史对话',
    aliases: ['switch', '搜索', '切换'],
    description: '搜索并跳转到历史会话',
    icon: AppIcons.search,
    kind: SlashCommandKind.app,
  ),
  SlashCommand(
    name: 'files',
    label: '工作区文件',
    aliases: ['文件'],
    description: '浏览、编辑或新建工作区文件',
    icon: AppIcons.files,
    kind: SlashCommandKind.app,
  ),
  SlashCommand(
    name: 'terminal',
    label: '打开终端',
    aliases: ['终端'],
    description: '启动本机 Shell 或 SSH 交互终端',
    icon: AppIcons.terminal,
    kind: SlashCommandKind.app,
  ),
  SlashCommand(
    name: 'mcp',
    label: 'MCP 服务管理',
    aliases: ['mcp服务'],
    description: '管理 settings.json 中的 Stdio / HTTP MCP 服务器',
    icon: AppIcons.plugin,
    kind: SlashCommandKind.app,
  ),
  SlashCommand(
    name: 'skills',
    label: 'Skills 技能',
    aliases: ['技能'],
    description: '查看、新建与重载 Agent Skills',
    icon: AppIcons.skill,
    kind: SlashCommandKind.app,
  ),
  SlashCommand(
    name: 'memory',
    label: '记忆与规则',
    aliases: ['rules', '记忆', '指令文件'],
    description: '查看或编辑全局与工作区 GEMINI.md',
    icon: AppIcons.document,
    kind: SlashCommandKind.app,
  ),
  SlashCommand(
    name: 'copy',
    label: '复制上条回复',
    aliases: ['复制'],
    description: '直接复制最近一条 AI 回复到剪贴板',
    icon: AppIcons.copy,
    kind: SlashCommandKind.app,
  ),
  SlashCommand(
    name: 'rename',
    label: '重命名对话',
    aliases: ['重命名'],
    description: '修改当前对话在侧边栏显示的标题',
    hint: '[新标题，留空则弹窗输入]',
    icon: AppIcons.rename,
    kind: SlashCommandKind.app,
  ),
  SlashCommand(
    name: 'phone',
    label: '手机操控',
    aliases: ['手机'],
    description: '配置无障碍 MCP 服务与 SafetyGate 闸门',
    icon: AppIcons.phoneControl,
    kind: SlashCommandKind.app,
  ),
  SlashCommand(
    name: 'share',
    label: '分享与导出',
    aliases: ['export', '导出', '分享'],
    description: '生成脱敏分享长图、Markdown 或回放包',
    icon: AppIcons.share,
    kind: SlashCommandKind.app,
  ),
  SlashCommand(
    name: 'config',
    label: '引擎与设置',
    aliases: ['settings', '设置'],
    description: '打开 settings.json 参数编辑器与偏好设置',
    icon: AppIcons.settings,
    kind: SlashCommandKind.app,
  ),
  SlashCommand(
    name: 'features',
    label: '全部功能',
    aliases: ['功能'],
    description: '打开 AGY Go 全部功能中枢',
    icon: AppIcons.allFeatures,
    kind: SlashCommandKind.app,
  ),
  SlashCommand(
    name: 'logout',
    label: '退出账号',
    aliases: ['退出'],
    description: '调用 ACP logout 断开当前登录态',
    icon: AppIcons.logout,
    kind: SlashCommandKind.app,
  ),
];

class SlashInput {
  const SlashInput(this.token, this.rest);

  final String token;
  final String? rest;

  bool get hasArgs => rest != null;
}

SlashInput? parseSlashInput(String text) {
  final trimmed = text.trimLeft();
  if (!trimmed.startsWith('/')) return null;
  final match = RegExp(r'\s').firstMatch(trimmed);
  if (match == null) return SlashInput(trimmed.substring(1), null);
  return SlashInput(trimmed.substring(1, match.start), trimmed.substring(match.start));
}

bool _isSubsequence(String needle, String haystack) {
  var i = 0;
  for (var j = 0; j < haystack.length && i < needle.length; j++) {
    if (haystack.codeUnitAt(j) == needle.codeUnitAt(i)) i++;
  }
  return i == needle.length;
}

List<SlashCommand> filterSlashCommands(List<SlashCommand> all, String token) {
  final q = token.trim().toLowerCase();
  if (q.isEmpty) return all;

  int? score(SlashCommand c) {
    final name = c.name.toLowerCase();
    final label = c.label.toLowerCase();
    final aliases = [for (final a in c.aliases) a.toLowerCase()];
    if (name.startsWith(q)) return 0;
    if (aliases.any((a) => a.startsWith(q)) || label.startsWith(q)) return 1;
    if (name.contains(q) ||
        label.contains(q) ||
        aliases.any((a) => a.contains(q))) {
      return 2;
    }
    if (_isSubsequence(q, name)) return 3;
    return null;
  }

  final scored = <(int, int, SlashCommand)>[
    for (final (i, c) in all.indexed)
      if (score(c) case final s?) (s, i, c),
  ]..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
  return [for (final (_, _, c) in scored) c];
}

SlashCommand? resolveSlashCommand(List<SlashCommand> all, String token) {
  final q = token.trim().toLowerCase();
  if (q.isEmpty) return null;
  for (final c in all) {
    if (c.name.toLowerCase() == q ||
        c.label.toLowerCase() == q ||
        c.aliases.any((a) => a.toLowerCase() == q)) {
      return c;
    }
  }
  return null;
}

sealed class SlashPaletteContent {
  const SlashPaletteContent();

  static SlashPaletteContent? of(List<SlashCommand> commands, String text) {
    final input = parseSlashInput(text);
    if (input == null) return null;
    if (!input.hasArgs) {
      return SlashPaletteMatches(
        filterSlashCommands(commands, input.token),
        typed: input.token.isNotEmpty,
      );
    }
    if (input.rest!.trim().isNotEmpty || text.contains('\n')) return null;
    final cmd = resolveSlashCommand(commands, input.token);
    if (cmd != null && (cmd.hint?.isNotEmpty ?? false)) {
      return SlashPaletteHint(cmd);
    }
    return null;
  }
}

final class SlashPaletteMatches extends SlashPaletteContent {
  const SlashPaletteMatches(this.commands, {this.typed = false});
  final List<SlashCommand> commands;
  final bool typed;
}

final class SlashPaletteHint extends SlashPaletteContent {
  const SlashPaletteHint(this.command);
  final SlashCommand command;
}

/// Unified command catalog merging:
/// 1. Built-in AGY Go + official Antigravity CLI (`agy`) commands
/// 2. Live commands advertised by `agy acp` (`available_commands_update`)
/// 3. Discovered Agent Skills (`SKILL.md`)
final slashCommandsProvider = Provider<List<SlashCommand>>((ref) {
  final liveAcp = ref.watch(
    chatProvider.select((c) => c.transcript.availableCommands),
  );
  final skills = ref.watch(agyConfigProvider.select((c) => c.skills));

  final seen = <String>{for (final c in builtInAgySlashCommands) c.name};
  final merged = <SlashCommand>[...builtInAgySlashCommands];

  for (final acp in liveAcp) {
    final name = acp.name.trim();
    if (name.isEmpty || !seen.add(name)) continue;
    merged.add(
      SlashCommand(
        name: name,
        label: name,
        description: acp.description ?? 'Antigravity 引擎动态指令',
        hint: acp.inputHint,
        icon: AppIcons.command,
        kind: SlashCommandKind.agy,
      ),
    );
  }

  for (final s in skills) {
    if (!seen.add(s.name)) continue;
    merged.add(
      SlashCommand(
        name: s.name,
        label: s.name,
        description: '${s.scope == 'workspace' ? '工作区技能' : '全局技能'} · ${s.description}',
        hint: '[附带说明，直接发送调用该 Skill]',
        icon: AppIcons.skill,
        kind: SlashCommandKind.skill,
      ),
    );
  }

  return merged;
});
