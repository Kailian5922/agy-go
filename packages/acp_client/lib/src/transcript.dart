import 'models.dart';

/// Immutable UI-friendly items folded from ACP `session/update` streams.
sealed class TranscriptItem {
  const TranscriptItem({required this.id, required this.timestamp});

  final String id;
  final DateTime timestamp;
}

final class UserTranscriptItem extends TranscriptItem {
  const UserTranscriptItem({
    required super.id,
    required super.timestamp,
    required this.text,
  });

  final String text;
}

final class AssistantTranscriptItem extends TranscriptItem {
  const AssistantTranscriptItem({
    required super.id,
    required super.timestamp,
    this.thought = '',
    this.text = '',
    this.toolCalls = const [],
    this.isStreaming = false,
    this.stopReason,
  });

  final String thought;
  final String text;
  final List<AcpToolCall> toolCalls;
  final bool isStreaming;
  final AcpStopReason? stopReason;

  bool get hasActivity =>
      thought.isNotEmpty || toolCalls.isNotEmpty;

  AssistantTranscriptItem copyWith({
    String? thought,
    String? text,
    List<AcpToolCall>? toolCalls,
    bool? isStreaming,
    AcpStopReason? stopReason,
  }) => AssistantTranscriptItem(
    id: id,
    timestamp: timestamp,
    thought: thought ?? this.thought,
    text: text ?? this.text,
    toolCalls: toolCalls ?? this.toolCalls,
    isStreaming: isStreaming ?? this.isStreaming,
    stopReason: stopReason ?? this.stopReason,
  );
}

/// Pure, immutable reducer folding ACP events into renderable conversation state.
class ChatTranscript {
  const ChatTranscript({
    this.items = const [],
    this.plan = const [],
    this.availableCommands = const [],
    this.modes,
    this.configOptions = const [],
    this.title,
    this.usage,
  });

  final List<TranscriptItem> items;
  final List<AcpPlanEntry> plan;
  final List<AcpSlashCommand> availableCommands;
  final AcpSessionModeState? modes;
  final List<AcpConfigOption> configOptions;
  final String? title;
  final AcpUsageInfo? usage;

  bool get isStreaming =>
      items.isNotEmpty &&
      items.last is AssistantTranscriptItem &&
      (items.last as AssistantTranscriptItem).isStreaming;

  ChatTranscript copyWith({
    List<TranscriptItem>? items,
    List<AcpPlanEntry>? plan,
    List<AcpSlashCommand>? availableCommands,
    AcpSessionModeState? modes,
    List<AcpConfigOption>? configOptions,
    String? title,
    AcpUsageInfo? usage,
  }) => ChatTranscript(
    items: items ?? this.items,
    plan: plan ?? this.plan,
    availableCommands: availableCommands ?? this.availableCommands,
    modes: modes ?? this.modes,
    configOptions: configOptions ?? this.configOptions,
    title: title ?? this.title,
    usage: usage ?? this.usage,
  );

  /// Records a locally submitted user prompt and opens a fresh streaming assistant turn.
  /// Closes any previously streaming assistant item so stale cursors never linger.
  ChatTranscript appendUserPrompt(String text, {DateTime? now}) {
    final ts = now ?? DateTime.now();
    final baseId = ts.microsecondsSinceEpoch;
    final settled = [
      for (final item in items)
        if (item is AssistantTranscriptItem && item.isStreaming)
          item.copyWith(isStreaming: false)
        else
          item,
    ];
    return copyWith(
      items: [
        ...settled,
        UserTranscriptItem(id: 'u_$baseId', timestamp: ts, text: text),
        AssistantTranscriptItem(
          id: 'a_$baseId',
          timestamp: ts,
          isStreaming: true,
        ),
      ],
    );
  }

  /// Marks all streaming assistant items finished when `session/prompt` resolves,
  /// errors, or is cancelled by the user.
  ChatTranscript finishTurn(AcpStopReason stopReason, {AcpUsageInfo? usage}) {
    final terminalToolStatus = stopReason == AcpStopReason.cancelled
        ? AcpToolStatus.cancelled
        : stopReason == AcpStopReason.unknown
        ? AcpToolStatus.failed
        : null;

    var changed = false;
    final nextItems = [
      for (final item in items)
        if (item is AssistantTranscriptItem && item.isStreaming)
          () {
            changed = true;
            final nextTools = terminalToolStatus == null
                ? item.toolCalls
                : [
                    for (final tc in item.toolCalls)
                      if (!tc.status.isTerminal)
                        AcpToolCall(
                          toolCallId: tc.toolCallId,
                          title: tc.title,
                          name: tc.name,
                          kind: tc.kind,
                          status: terminalToolStatus,
                          locations: tc.locations,
                          content: tc.content,
                          rawInput: tc.rawInput,
                          rawOutput: tc.rawOutput,
                        )
                      else
                        tc,
                  ];
            return item.copyWith(
              isStreaming: false,
              stopReason: stopReason,
              toolCalls: nextTools,
            );
          }()
        else
          item,
    ];
    return copyWith(
      items: changed ? nextItems : items,
      usage: usage ?? this.usage,
    );
  }

  /// Clears streaming flags on all replayed history items after `session/load` or `session/resume`.
  ChatTranscript finishAllStreaming() {
    var changed = false;
    final nextItems = [
      for (final item in items)
        if (item is AssistantTranscriptItem && item.isStreaming)
          () {
            changed = true;
            return item.copyWith(isStreaming: false);
          }()
        else
          item,
    ];
    return changed ? copyWith(items: nextItems) : this;
  }

  /// Applies a single ACP `session/update` notification.
  ChatTranscript applyUpdate(AcpSessionUpdate update, {DateTime? now}) {
    final ts = now ?? DateTime.now();
    switch (update) {
      case UserMessageChunkUpdate(:final content):
        final chunkText = _blockText(content);
        if (chunkText.isEmpty) return this;
        if (items.isNotEmpty && items.last is UserTranscriptItem) {
          final last = items.last as UserTranscriptItem;
          final next = List<TranscriptItem>.from(items)
            ..[items.length - 1] = UserTranscriptItem(
              id: last.id,
              timestamp: last.timestamp,
              text: '${last.text}$chunkText',
            );
          return copyWith(items: next);
        }
        final settled = [
          for (final item in items)
            if (item is AssistantTranscriptItem && item.isStreaming)
              item.copyWith(isStreaming: false)
            else
              item,
        ];
        return copyWith(
          items: [
            ...settled,
            UserTranscriptItem(
              id: 'u_${items.length}_${ts.microsecondsSinceEpoch}',
              timestamp: ts,
              text: chunkText,
            ),
          ],
        );

      case AgentMessageChunkUpdate(:final content):
        final chunkText = _blockText(content);
        if (chunkText.isEmpty) return this;
        return _updateLastAssistant(
          ts,
          (a) => a.copyWith(text: '${a.text}$chunkText'),
        );

      case AgentThoughtChunkUpdate(:final content):
        final chunkText = _blockText(content);
        if (chunkText.isEmpty) return this;
        return _updateLastAssistant(
          ts,
          (a) => a.copyWith(thought: '${a.thought}$chunkText'),
        );

      case ToolCallCreatedUpdate(:final toolCall):
        return _updateLastAssistant(ts, (a) {
          final existingIdx = a.toolCalls.indexWhere(
            (t) => t.toolCallId == toolCall.toolCallId,
          );
          final nextTools = List<AcpToolCall>.from(a.toolCalls);
          if (existingIdx >= 0) {
            nextTools[existingIdx] = toolCall;
          } else {
            nextTools.add(toolCall);
          }
          return a.copyWith(toolCalls: nextTools);
        });

      case ToolCallPatchedUpdate(:final toolCallId, :final patch):
        return _updateLastAssistant(ts, (a) {
          final existingIdx = a.toolCalls.indexWhere(
            (t) => t.toolCallId == toolCallId,
          );
          final nextTools = List<AcpToolCall>.from(a.toolCalls);
          if (existingIdx >= 0) {
            nextTools[existingIdx] = nextTools[existingIdx].mergePatch(patch);
          } else {
            nextTools.add(AcpToolCall.fromJson(patch));
          }
          return a.copyWith(toolCalls: nextTools);
        });

      case PlanUpdate(:final entries):
        return copyWith(plan: entries);

      case AvailableCommandsUpdate(:final commands):
        return copyWith(availableCommands: commands);

      case CurrentModeUpdate(:final currentModeId):
        final current = modes;
        return copyWith(
          modes: AcpSessionModeState(
            currentModeId: currentModeId,
            availableModes: current?.availableModes ?? const [],
          ),
        );

      case ConfigOptionUpdate(:final configOptions):
        return copyWith(configOptions: configOptions);

      case SessionInfoUpdate(:final title):
        return copyWith(title: title ?? this.title);

      case UsageSessionUpdate(:final usage):
        return copyWith(usage: usage);

      case UnknownSessionUpdate():
        return this;
    }
  }

  ChatTranscript _updateLastAssistant(
    DateTime ts,
    AssistantTranscriptItem Function(AssistantTranscriptItem) transform,
  ) {
    final nextItems = List<TranscriptItem>.from(items);
    if (nextItems.isEmpty || nextItems.last is! AssistantTranscriptItem) {
      final created = AssistantTranscriptItem(
        id: 'a_${nextItems.length}_${ts.microsecondsSinceEpoch}',
        timestamp: ts,
        isStreaming: true,
      );
      nextItems.add(transform(created));
    } else {
      nextItems[nextItems.length - 1] = transform(
        nextItems.last as AssistantTranscriptItem,
      );
    }
    return copyWith(items: nextItems);
  }

  static String _blockText(AcpContentBlock block) => switch (block) {
    AcpTextBlock(:final text) => text,
    AcpResourceLinkBlock(:final title, :final name, :final uri) =>
      '[${title ?? name}]($uri)',
    AcpImageBlock(:final mimeType) => '[image: $mimeType]',
  };
}
