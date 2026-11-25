import 'dart:convert';

import 'package:acp_client/acp_client.dart';

/// Utilities for secret redaction, Markdown export, and structured JSON replay bundles.
class ConversationExport {
  const ConversationExport._();

  static const schemaVersion = 'agy-go-replay/v1';

  /// Redacts API keys, OAuth tokens, PEM private keys, and bearer credentials before export.
  static String redactSecrets(String input) {
    return input
        .replaceAll(
          RegExp(
            r'-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----',
          ),
          '[REDACTED_PRIVATE_KEY]',
        )
        .replaceAll(RegExp(r'AIza[0-9A-Za-z_-]{20,}'), '[REDACTED_GEMINI_KEY]')
        .replaceAll(RegExp(r'ya29\.[0-9A-Za-z._-]{20,}'), '[REDACTED_OAUTH_TOKEN]')
        .replaceAll(RegExp(r'sk-[0-9A-Za-z_-]{20,}'), '[REDACTED_API_KEY]')
        .replaceAll(
          RegExp(r'Bearer\s+[0-9A-Za-z._-]{16,}', caseSensitive: false),
          'Bearer [REDACTED]',
        );
  }

  /// Exports a transcript as human-readable Markdown with automatic secret redaction.
  static String toMarkdown(
    ChatTranscript transcript, {
    String? title,
    String? hostLabel,
  }) {
    final buf = StringBuffer();
    buf.writeln('# ${title ?? transcript.title ?? 'AGY Go 对话记录'}');
    if (hostLabel != null) {
      buf.writeln('\n> 主机：$hostLabel');
    }
    buf.writeln();

    for (final item in transcript.items) {
      switch (item) {
        case UserTranscriptItem(:final text):
          buf.writeln('## 用户');
          buf.writeln();
          buf.writeln(redactSecrets(text));
          buf.writeln();
        case AssistantTranscriptItem(:final thought, :final text, :final toolCalls):
          buf.writeln('## Antigravity');
          buf.writeln();
          if (thought.isNotEmpty) {
            buf.writeln('<details><summary>思考过程</summary>\n');
            buf.writeln(redactSecrets(thought));
            buf.writeln('\n</details>\n');
          }
          if (toolCalls.isNotEmpty) {
            buf.writeln('**工具调用（${toolCalls.length}）**');
            for (final tc in toolCalls) {
              buf.writeln('- `${tc.kind.name}` ${redactSecrets(tc.title)} (${tc.status.name})');
            }
            buf.writeln();
          }
          if (text.isNotEmpty) {
            buf.writeln(redactSecrets(text));
            buf.writeln();
          }
      }
    }
    return buf.toString().trimRight();
  }

  /// Serializes a transcript into a portable replay JSON bundle.
  static String toReplayJson(
    ChatTranscript transcript, {
    String? title,
    String? hostLabel,
  }) {
    final payload = <String, Object?>{
      'schema': schemaVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'title': title ?? transcript.title ?? 'AGY Go Replay',
      'host': hostLabel ?? 'AGY Go',
      'items': [
        for (final item in transcript.items)
          switch (item) {
            UserTranscriptItem(:final id, :final timestamp, :final text) => {
              'role': 'user',
              'id': id,
              'timestamp': timestamp.toUtc().toIso8601String(),
              'text': redactSecrets(text),
            },
            AssistantTranscriptItem(
              :final id,
              :final timestamp,
              :final thought,
              :final text,
              :final toolCalls,
            ) =>
              {
                'role': 'assistant',
                'id': id,
                'timestamp': timestamp.toUtc().toIso8601String(),
                'thought': redactSecrets(thought),
                'text': redactSecrets(text),
                'toolCalls': [
                  for (final tc in toolCalls)
                    {
                      'toolCallId': tc.toolCallId,
                      'title': redactSecrets(tc.title),
                      'kind': tc.kind.name,
                      'status': tc.status.name,
                    },
                ],
              },
          },
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Parses an exported replay JSON bundle back into an immutable [ChatTranscript].
  static ChatTranscript parseReplayJson(String rawJson) {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map) {
      throw const FormatException('Invalid replay bundle: expected JSON object');
    }
    final schema = decoded['schema'];
    if (schema != schemaVersion) {
      throw FormatException('Unsupported replay schema: $schema');
    }
    final title = decoded['title'] as String?;
    final rawItems = decoded['items'];
    final items = <TranscriptItem>[];
    if (rawItems is List) {
      for (var i = 0; i < rawItems.length; i++) {
        final raw = rawItems[i];
        if (raw is! Map) continue;
        final role = raw['role'] as String?;
        final id = raw['id'] as String? ?? 'replay_$i';
        final ts = DateTime.tryParse(raw['timestamp'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        if (role == 'user') {
          items.add(
            UserTranscriptItem(
              id: id,
              timestamp: ts,
              text: raw['text'] as String? ?? '',
            ),
          );
        } else if (role == 'assistant') {
          final rawTools = raw['toolCalls'];
          final tools = <AcpToolCall>[];
          if (rawTools is List) {
            for (final t in rawTools.whereType<Map>()) {
              tools.add(AcpToolCall.fromJson(Map<String, Object?>.from(t)));
            }
          }
          items.add(
            AssistantTranscriptItem(
              id: id,
              timestamp: ts,
              thought: raw['thought'] as String? ?? '',
              text: raw['text'] as String? ?? '',
              toolCalls: tools,
            ),
          );
        }
      }
    }
    return ChatTranscript(items: items, title: title);
  }
}
