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

/// Per-turn generation throughput metrics attached to a completed assistant reply.
class AcpTurnMetrics {
  const AcpTurnMetrics({
    required this.tokensPerSecond,
    required this.tokens,
    required this.generationSeconds,
    this.estimated = true,
  });

  final double tokensPerSecond;
  final int tokens;
  final double generationSeconds;
  final bool estimated;
}

/// Chronological segment inside a single assistant turn so interleaved
/// thinking ("大思考" / "小思考"), tool calls ("小编辑"), and messages stay
/// in their true real-time order instead of flattening all thoughts to the top.
sealed class AssistantTimelineEntry {
  const AssistantTimelineEntry({required this.id});
  final String id;
}

final class ThoughtTimelineEntry extends AssistantTimelineEntry {
  const ThoughtTimelineEntry({required super.id, required this.text});
  final String text;
}

final class ToolTimelineEntry extends AssistantTimelineEntry {
  const ToolTimelineEntry({required super.id, required this.toolCallId});
  final String toolCallId;
}

final class MessageTimelineEntry extends AssistantTimelineEntry {
  const MessageTimelineEntry({required super.id, required this.text});
  final String text;
}

final class AssistantTranscriptItem extends TranscriptItem {
  const AssistantTranscriptItem({
    required super.id,
    required super.timestamp,
    this.thought = '',
    this.text = '',
    this.toolCalls = const [],
    this.timeline = const [],
    this.isStreaming = false,
    this.stopReason,
    this.metrics,
  });

  final String thought;
  final String text;
  final List<AcpToolCall> toolCalls;
  final List<AssistantTimelineEntry> timeline;
  final bool isStreaming;
  final AcpStopReason? stopReason;
  final AcpTurnMetrics? metrics;

  bool get hasActivity =>
      thought.isNotEmpty || toolCalls.isNotEmpty;

  /// Chronological entries for rendering: uses the recorded [timeline] when
  /// present, or synthesizes an equivalent sequence for directly-constructed items.
  List<AssistantTimelineEntry> get effectiveTimeline {
    if (timeline.isNotEmpty) return timeline;
    return [
      if (thought.isNotEmpty)
        ThoughtTimelineEntry(id: '${id}_thought', text: thought),
      for (final tc in toolCalls)
        ToolTimelineEntry(id: '${id}_tc_${tc.toolCallId}', toolCallId: tc.toolCallId),
      if (text.isNotEmpty)
        MessageTimelineEntry(id: '${id}_msg', text: text),
    ];
  }

  AcpToolCall? toolCallById(String toolCallId) {
    for (final tc in toolCalls) {
      if (tc.toolCallId == toolCallId) return tc;
    }
    return null;
  }

  AssistantTranscriptItem copyWith({
    String? thought,
    String? text,
    List<AcpToolCall>? toolCalls,
    List<AssistantTimelineEntry>? timeline,
    bool? isStreaming,
    AcpStopReason? stopReason,
    AcpTurnMetrics? metrics,
  }) => AssistantTranscriptItem(
    id: id,
    timestamp: timestamp,
    thought: thought ?? this.thought,
    text: text ?? this.text,
    toolCalls: toolCalls ?? this.toolCalls,
    timeline: timeline ?? this.timeline,
    isStreaming: isStreaming ?? this.isStreaming,
    stopReason: stopReason ?? this.stopReason,
    metrics: metrics ?? this.metrics,
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
  ChatTranscript finishTurn(
    AcpStopReason stopReason, {
    AcpUsageInfo? usage,
    AcpTurnMetrics? metrics,
  }) {
    final terminalToolStatus = switch (stopReason) {
      AcpStopReason.cancelled => AcpToolStatus.cancelled,
      AcpStopReason.unknown => AcpToolStatus.failed,
      _ => AcpToolStatus.completed,
    };

    var changed = false;
    final nextItems = [
      for (var i = 0; i < items.length; i++)
        if (items[i] is AssistantTranscriptItem &&
            (items[i] as AssistantTranscriptItem).isStreaming)
          () {
            final item = items[i] as AssistantTranscriptItem;
            changed = true;
            final nextTools = [
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
                    meta: tc.meta,
                  )
                else
                  tc,
            ];
            return item.copyWith(
              isStreaming: false,
              stopReason: stopReason,
              toolCalls: nextTools,
              metrics: i == items.length - 1
                  ? (metrics ?? item.metrics)
                  : item.metrics,
            );
          }()
        else
          items[i],
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
        if (item is AssistantTranscriptItem &&
            (item.isStreaming ||
                item.toolCalls.any((tc) => !tc.status.isTerminal)))
          () {
            changed = true;
            return item.copyWith(
              isStreaming: false,
              toolCalls: [
                for (final tc in item.toolCalls)
                  if (!tc.status.isTerminal)
                    AcpToolCall(
                      toolCallId: tc.toolCallId,
                      title: tc.title,
                      name: tc.name,
                      kind: tc.kind,
                      status: AcpToolStatus.completed,
                      locations: tc.locations,
                      content: tc.content,
                      rawInput: tc.rawInput,
                      rawOutput: tc.rawOutput,
                      meta: tc.meta,
                    )
                  else
                    tc,
              ],
            );
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
        return _updateLastAssistant(ts, (a) {
          final nextTimeline = List<AssistantTimelineEntry>.from(a.timeline);
          if (nextTimeline.isNotEmpty &&
              nextTimeline.last is MessageTimelineEntry) {
            final prev = nextTimeline.last as MessageTimelineEntry;
            nextTimeline[nextTimeline.length - 1] = MessageTimelineEntry(
              id: prev.id,
              text: '${prev.text}$chunkText',
            );
          } else {
            nextTimeline.add(
              MessageTimelineEntry(
                id: '${a.id}_msg_${nextTimeline.length}',
                text: chunkText,
              ),
            );
          }
          final sep =
              a.text.isNotEmpty &&
                  a.timeline.isNotEmpty &&
                  a.timeline.last is! MessageTimelineEntry
              ? '\n\n'
              : '';
          return a.copyWith(
            text: '${a.text}$sep$chunkText',
            timeline: nextTimeline,
          );
        });

      case AgentThoughtChunkUpdate(:final content):
        final chunkText = _blockText(content);
        if (chunkText.isEmpty) return this;
        return _updateLastAssistant(ts, (a) {
          final nextTimeline = List<AssistantTimelineEntry>.from(a.timeline);
          final startingNewThoughtBlock =
              nextTimeline.isNotEmpty &&
              nextTimeline.last is! ThoughtTimelineEntry;
          if (nextTimeline.isNotEmpty &&
              nextTimeline.last is ThoughtTimelineEntry) {
            final prev = nextTimeline.last as ThoughtTimelineEntry;
            nextTimeline[nextTimeline.length - 1] = ThoughtTimelineEntry(
              id: prev.id,
              text: '${prev.text}$chunkText',
            );
          } else {
            nextTimeline.add(
              ThoughtTimelineEntry(
                id: '${a.id}_th_${nextTimeline.length}',
                text: chunkText,
              ),
            );
          }
          final sep = a.thought.isNotEmpty && startingNewThoughtBlock
              ? '\n\n'
              : '';
          return a.copyWith(
            thought: '${a.thought}$sep$chunkText',
            timeline: nextTimeline,
          );
        });

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
          final nextTimeline = List<AssistantTimelineEntry>.from(a.timeline);
          final hasEntry = nextTimeline.any(
            (e) => e is ToolTimelineEntry && e.toolCallId == toolCall.toolCallId,
          );
          if (!hasEntry) {
            nextTimeline.add(
              ToolTimelineEntry(
                id: '${a.id}_tc_${toolCall.toolCallId}',
                toolCallId: toolCall.toolCallId,
              ),
            );
          }
          return a.copyWith(toolCalls: nextTools, timeline: nextTimeline);
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
          final nextTimeline = List<AssistantTimelineEntry>.from(a.timeline);
          final hasEntry = nextTimeline.any(
            (e) => e is ToolTimelineEntry && e.toolCallId == toolCallId,
          );
          if (!hasEntry) {
            nextTimeline.add(
              ToolTimelineEntry(
                id: '${a.id}_tc_$toolCallId',
                toolCallId: toolCallId,
              ),
            );
          }
          return a.copyWith(toolCalls: nextTools, timeline: nextTimeline);
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

      case AgentStatusUpdate():
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
