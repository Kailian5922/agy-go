import 'dart:async';

import 'package:acp_client/acp_client.dart';
import 'package:test/test.dart';

void main() {
  group('AcpClient & ChatTranscript', () {
    test('initialize, create session, stream chunks/tools, approve permission, finish turn', () async {
      final (clientTransport, agentTransport) = MemoryAcpTransport.pair();
      final agent = AcpJsonRpcPeer(agentTransport);
      final client = AcpClient(clientTransport);

      agent.onRequest('initialize', (params) async {
        expect(params['protocolVersion'], 1);
        return {
          'protocolVersion': 1,
          'agentInfo': {'name': 'antigravity-cli', 'version': '1.5.17'},
          'agentCapabilities': {
            'loadSession': true,
            'promptCapabilities': {'image': true},
            'sessionCapabilities': {'list': {}, 'resume': {}, 'delete': {}},
          },
          'authMethods': [
            {'id': 'oauth-personal', 'name': 'Google Account'},
            {'id': 'gemini-api-key', 'name': 'Gemini API Key'},
          ],
        };
      });

      agent.onRequest('session/new', (params) async {
        expect(params['cwd'], '/root/workspace');
        return {
          'sessionId': 'sess_1',
          'modes': {
            'currentModeId': 'code',
            'availableModes': [
              {'id': 'code', 'name': 'Code'},
              {'id': 'plan', 'name': 'Plan'},
            ],
          },
          'configOptions': [
            {
              'id': 'model',
              'name': 'Model',
              'type': 'select',
              'category': 'model',
              'currentValue': 'gemini-4-neon',
              'options': [
                {'value': 'gemini-4-neon', 'name': 'Gemini 4 Neon'},
                {'value': 'gemini-3.8-flash', 'name': 'Gemini 3.8 Flash'},
              ],
            },
          ],
        };
      });

      agent.onRequest('session/prompt', (params) async {
        final sid = params['sessionId']! as String;
        await agent.sendNotification('session/update', {
          'sessionId': sid,
          'update': {
            'sessionUpdate': 'agent_thought_chunk',
            'content': {'type': 'text', 'text': 'Checking files...'},
          },
        });
        await agent.sendNotification('session/update', {
          'sessionId': sid,
          'update': {
            'sessionUpdate': 'tool_call',
            'toolCallId': 'tc_1',
            'title': 'Edit lib/main.dart',
            'kind': 'edit',
            'status': 'pending',
          },
        });

        final permResp = await agent.sendRequest('session/request_permission', {
          'sessionId': sid,
          'toolCall': {
            'toolCallId': 'tc_1',
            'title': 'Edit lib/main.dart',
            'kind': 'edit',
            'status': 'pending',
          },
          'options': [
            {'optionId': 'allow_1', 'name': 'Allow once', 'kind': 'allow_once'},
            {'optionId': 'deny_1', 'name': 'Reject', 'kind': 'reject_once'},
          ],
        });
        expect((permResp['outcome'] as Map)['outcome'], 'selected');
        expect((permResp['outcome'] as Map)['optionId'], 'allow_1');

        await agent.sendNotification('session/update', {
          'sessionId': sid,
          'update': {
            'sessionUpdate': 'tool_call_update',
            'toolCallId': 'tc_1',
            'status': 'completed',
            'content': [
              {
                'type': 'diff',
                'path': 'lib/main.dart',
                'oldText': 'void main() {}',
                'newText': 'void main() => runApp(App());',
              },
            ],
          },
        });
        await agent.sendNotification('session/update', {
          'sessionId': sid,
          'update': {
            'sessionUpdate': 'agent_message_chunk',
            'content': {'type': 'text', 'text': 'Updated `lib/main.dart`.'},
          },
        });
        return {'stopReason': 'end_turn'};
      });

      var transcript = const ChatTranscript();
      final updateSub = client.updates.listen((event) {
        transcript = transcript.applyUpdate(event.update);
      });
      final permSub = client.permissionRequests.listen((pending) {
        expect(pending.request.toolCall.title, 'Edit lib/main.dart');
        pending.select('allow_1');
      });

      final init = await client.initialize();
      expect(init.agentInfo?.name, 'antigravity-cli');
      expect(init.capabilities.loadSession, isTrue);
      expect(init.capabilities.canListSessions, isTrue);

      final handle = await client.newSession(cwd: '/root/workspace');
      expect(handle.sessionId, 'sess_1');
      expect(handle.configOptions.single.currentValue, 'gemini-4-neon');

      transcript = transcript.appendUserPrompt('Update main.dart');
      final result = await client.promptText(handle.sessionId, 'Update main.dart');
      transcript = transcript.finishTurn(result.stopReason);

      // Flush microtask notifications.
      await Future<void>.delayed(Duration.zero);

      expect(result.stopReason, AcpStopReason.endTurn);
      expect(transcript.items.length, 2);
      final assistant = transcript.items.last as AssistantTranscriptItem;
      expect(assistant.isStreaming, isFalse);
      expect(assistant.thought, 'Checking files...');
      expect(assistant.text, 'Updated `lib/main.dart`.');
      expect(assistant.toolCalls.single.status, AcpToolStatus.completed);
      expect(
        assistant.toolCalls.single.content.single,
        isA<AcpDiffToolContent>(),
      );

      await updateSub.cancel();
      await permSub.cancel();
      await client.close();
      await agent.close();
    });

    test('cancel resolves pending permissions as cancelled per ACP spec', () async {
      final (clientTransport, agentTransport) = MemoryAcpTransport.pair();
      final agent = AcpJsonRpcPeer(agentTransport);
      final client = AcpClient(clientTransport);

      final cancelledNotification = Completer<String>();
      agent.onNotification('session/cancel', (params) {
        cancelledNotification.complete(params['sessionId']! as String);
      });

      final permArrived = Completer<PendingPermission>();
      final permSub = client.permissionRequests.listen(permArrived.complete);

      final permFuture = agent.sendRequest('session/request_permission', {
        'sessionId': 'sess_cancel',
        'toolCall': {'toolCallId': 'tc_9', 'title': 'Run rm -rf', 'kind': 'execute'},
        'options': [
          {'optionId': 'allow', 'name': 'Allow', 'kind': 'allow_once'},
        ],
      });

      await permArrived.future;
      await client.cancel('sess_cancel');

      final permResult = await permFuture;
      expect((permResult['outcome'] as Map)['outcome'], 'cancelled');
      expect(await cancelledNotification.future, 'sess_cancel');

      await permSub.cancel();
      await client.close();
      await agent.close();
    });

    test('AcpSessionHandle synthesizes model option from models.availableModels fallback and detects thought_level', () {
      final handle = AcpSessionHandle.fromJson({
        'sessionId': 's_fallback',
        'models': {
          'currentModelId': 'gemini-4-hydrogen',
          'availableModels': [
            {'modelId': 'gemini-4-hydrogen', 'name': 'Gemini 4 Hydrogen'},
            {'modelId': 'claude-opus-5-5', 'name': 'Claude Opus 5.5'},
          ],
        },
        'configOptions': [
          {
            'id': 'thought_level',
            'name': 'Thought Level',
            'type': 'select',
            'category': 'thought_level',
            'currentValue': 'high',
            'options': [
              {'value': 'low', 'name': 'Low'},
              {'value': 'high', 'name': 'High'},
            ],
          },
        ],
      });

      final modelOpt = handle.configOptions.where((o) => o.isModelOption).firstOrNull;
      final thoughtOpt = handle.configOptions.where((o) => o.isThoughtLevelOption).firstOrNull;
      expect(modelOpt, isNotNull);
      expect(modelOpt!.currentValue, 'gemini-4-hydrogen');
      expect(modelOpt.options.length, 2);
      expect(thoughtOpt, isNotNull);
      expect(thoughtOpt!.currentValue, 'high');
    });

    test('replayed turns settle prior cursors and finishAllStreaming clears all streaming flags', () {
      var t = const ChatTranscript();
      t = t.applyUpdate(const UserMessageChunkUpdate(AcpTextBlock('turn 1')));
      t = t.applyUpdate(const AgentMessageChunkUpdate(AcpTextBlock('network error 1')));
      t = t.applyUpdate(const UserMessageChunkUpdate(AcpTextBlock('turn 2')));
      t = t.applyUpdate(const AgentMessageChunkUpdate(AcpTextBlock('network error 2')));

      // Turn 1 assistant was settled when turn 2 user chunk arrived; turn 2 is still streaming until replay ends.
      expect((t.items[1] as AssistantTranscriptItem).isStreaming, isFalse);
      expect(t.isStreaming, isTrue);

      t = t.finishAllStreaming();
      expect(t.isStreaming, isFalse);
      for (final item in t.items.whereType<AssistantTranscriptItem>()) {
        expect(item.isStreaming, isFalse);
      }
    });

    test('finishTurn on cancel/unknown settles streaming flags and dangling tool calls, appendUserPrompt closes prior cursor', () {
      var t = const ChatTranscript().appendUserPrompt('first');
      t = t.applyUpdate(
        const ToolCallCreatedUpdate(
          AcpToolCall(
            toolCallId: 'tc_stuck',
            title: 'Read file',
            kind: AcpToolKind.read,
            status: AcpToolStatus.inProgress,
          ),
        ),
      );
      expect(t.isStreaming, isTrue);

      // Even if a new prompt is appended before finishing, prior streaming cursor is closed.
      final second = t.appendUserPrompt('second');
      expect((second.items[1] as AssistantTranscriptItem).isStreaming, isFalse);
      expect((second.items[3] as AssistantTranscriptItem).isStreaming, isTrue);

      // Cancelling settles both streaming state and dangling non-terminal tool calls.
      final cancelled = t.finishTurn(AcpStopReason.cancelled);
      expect(cancelled.isStreaming, isFalse);
      final assistant = cancelled.items.last as AssistantTranscriptItem;
      expect(assistant.stopReason, AcpStopReason.cancelled);
      expect(assistant.toolCalls.single.status, AcpToolStatus.cancelled);

      final failed = t.finishTurn(AcpStopReason.unknown);
      expect(
        (failed.items.last as AssistantTranscriptItem).toolCalls.single.status,
        AcpToolStatus.failed,
      );
    });

    test('LineStreamAcpTransport serializes overlapping async writes and isolates write errors', () async {
      final input = StreamController<List<int>>();
      var inFlight = 0;
      var maxInFlight = 0;
      final written = <String>[];
      var callCount = 0;

      final transport = LineStreamAcpTransport(
        kind: 'test',
        inputBytes: input.stream,
        writeBytes: (bytes) async {
          inFlight++;
          if (inFlight > maxInFlight) maxInFlight = inFlight;
          callCount++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          inFlight--;
          if (callCount == 2) {
            throw StateError('transient write error');
          }
          written.add(String.fromCharCodes(bytes).trim());
        },
        onClose: () async => input.close(),
      );
      addTearDown(transport.close);

      final f1 = transport.send({'seq': 1});
      final f2 = transport.send({'seq': 2});
      final f3 = transport.send({'seq': 3});

      await f1;
      await expectLater(f2, throwsA(isA<AcpTransportException>()));
      await f3;

      expect(maxInFlight, 1);
      expect(written, ['{"seq":1}', '{"seq":3}']);
    });

    test('AcpClient.otherNotifications forwards non-session/update retry & progress notices', () async {
      final (clientTransport, agentTransport) = MemoryAcpTransport.pair();
      final client = AcpClient(clientTransport);
      final agent = AcpJsonRpcPeer(agentTransport);
      addTearDown(() async {
        await client.close();
        await agent.close();
      });

      final received = <AcpRawNotification>[];
      final sub = client.otherNotifications.listen(received.add);
      addTearDown(sub.cancel);

      await agent.sendNotification(r'$/progress', {
        'message': 'retrying attempt 2/5 in 4s',
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(received.length, 1);
      expect(received.single.method, r'$/progress');
      expect(received.single.params['message'], 'retrying attempt 2/5 in 4s');
    });

    test('AcpUsageInfo parses output/thought tokens and finishTurn attaches AcpTurnMetrics', () {
      final snake = AcpUsageInfo.fromJson({
        'used': 4096,
        'size': 128000,
        'input_tokens': 1000,
        'output_tokens': 240,
        'thought_tokens': 160,
        'total_tokens': 1400,
      });
      expect(snake.inputTokens, 1000);
      expect(snake.outputTokens, 240);
      expect(snake.thoughtTokens, 160);
      expect(snake.generatedTokens, 400);

      final camel = AcpUsageInfo.fromJson({
        'completionTokens': 85,
        'reasoningTokens': 35,
      });
      expect(camel.generatedTokens, 120);

      var t = const ChatTranscript().appendUserPrompt('hello');
      t = t.applyUpdate(
        const AgentMessageChunkUpdate(AcpTextBlock('world response')),
      );
      const metrics = AcpTurnMetrics(
        tokensPerSecond: 52.4,
        tokens: 400,
        generationSeconds: 7.63,
        estimated: false,
      );
      t = t.finishTurn(AcpStopReason.endTurn, usage: snake, metrics: metrics);
      final assistant = t.items.last as AssistantTranscriptItem;
      expect(assistant.isStreaming, isFalse);
      expect(assistant.metrics, isNotNull);
      expect(assistant.metrics!.tokensPerSecond, closeTo(52.4, 0.01));
      expect(assistant.metrics!.tokens, 400);
      expect(assistant.metrics!.estimated, isFalse);
    });

    test('AcpToolCall preserves status/diffs across partial patches, infers kind, and extracts live rawInput diffs', () {
      // Kind inferred from name/title when omitted by backend
      final inferredEdit = AcpToolCall.fromJson({
        'toolCallId': 'edit-1',
        'name': 'replace_file_content',
        'title': 'Edit lib/main.dart',
        'status': 'working',
        'rawInput': {
          'TargetFile': '/repo/lib/main.dart',
          'TargetContent': 'final a = 1;\n',
          'ReplacementContent': 'final a = 2;\nfinal b = 3;\n',
        },
      });
      expect(inferredEdit.kind, AcpToolKind.edit);
      expect(inferredEdit.status, AcpToolStatus.inProgress);
      expect(inferredEdit.modifiesFiles, isTrue);
      expect(inferredEdit.effectiveDiffs.length, 1);
      expect(inferredEdit.effectiveDiffs.single.path, '/repo/lib/main.dart');
      expect(inferredEdit.effectiveDiffs.single.oldText, 'final a = 1;\n');
      expect(
        inferredEdit.effectiveDiffs.single.newText,
        'final a = 2;\nfinal b = 3;\n',
      );

      // Partial patch with null status & empty content/locations must NOT reset status or wipe content!
      final withExplicitDiff = inferredEdit.mergePatch({
        'status': 'in_progress',
        'locations': [
          {'path': '/repo/lib/main.dart', 'line': 10},
        ],
        'content': [
          {
            'type': 'diff',
            'path': '/repo/lib/main.dart',
            'old_text': 'final a = 1;\n',
            'new_text': 'final a = 2;\n',
          },
        ],
      });
      final afterPartialPatch = withExplicitDiff.mergePatch({
        'status': null,
        'content': const <Object?>[],
        'locations': const <Object?>[],
        'rawOutput': 'patched 1 hunk',
      });
      expect(afterPartialPatch.status, AcpToolStatus.inProgress);
      expect(afterPartialPatch.locations.length, 1);
      expect(afterPartialPatch.effectiveDiffs.length, 1);
      expect(afterPartialPatch.rawOutput, 'patched 1 hunk');

      // Multi-chunk ReplacementChunks in rawInput also yields live diffs
      final multiChunk = AcpToolCall.fromJson({
        'toolCallId': 'edit-2',
        'name': 'multi_replace_file_content',
        'title': 'Multi-edit app.dart',
        'status': 'in_progress',
        'rawInput': {
          'TargetFile': '/repo/lib/app.dart',
          'ReplacementChunks': [
            {
              'TargetContent': 'old1',
              'ReplacementContent': 'new1',
            },
            {
              'TargetContent': 'old2',
              'ReplacementContent': 'new2',
            },
          ],
        },
      });
      expect(multiChunk.effectiveDiffs.length, 2);
      expect(multiChunk.effectiveDiffs[0].newText, 'new1');
      expect(multiChunk.effectiveDiffs[1].newText, 'new2');
    });

    test('AgentStatusUpdate parses status updates and ChatTranscript keeps interleaved timeline chronological', () {
      final statusUpdate = AcpSessionUpdate.fromJson({
        'sessionUpdate': 'status_update',
        'phase': 'analyzing',
        'message': 'Scanning workspace files',
      });
      expect(statusUpdate, isA<AgentStatusUpdate>());
      final s = statusUpdate as AgentStatusUpdate;
      expect(s.status, 'analyzing');
      expect(s.detail, 'Scanning workspace files');

      var t = const ChatTranscript().appendUserPrompt('帮我修改文件');
      t = t.applyUpdate(
        const AgentThoughtChunkUpdate(AcpTextBlock('大思考第一段：先看代码结构')),
      );
      t = t.applyUpdate(
        const ToolCallCreatedUpdate(
          AcpToolCall(
            toolCallId: 'tc-read',
            title: '读取 lib/main.dart',
            kind: AcpToolKind.read,
            status: AcpToolStatus.inProgress,
          ),
        ),
      );
      t = t.applyUpdate(
        const ToolCallPatchedUpdate(
          toolCallId: 'tc-read',
          patch: {'status': 'completed'},
        ),
      );
      t = t.applyUpdate(
        const AgentThoughtChunkUpdate(AcpTextBlock('小思考：定位到需要修改的位置')),
      );
      t = t.applyUpdate(
        const ToolCallCreatedUpdate(
          AcpToolCall(
            toolCallId: 'tc-edit',
            title: '编辑 lib/main.dart',
            kind: AcpToolKind.edit,
            status: AcpToolStatus.inProgress,
          ),
        ),
      );
      t = t.applyUpdate(
        const AgentMessageChunkUpdate(AcpTextBlock('已经帮你完成了修改。')),
      );

      final assistant = t.items.last as AssistantTranscriptItem;
      expect(assistant.timeline.length, 5);
      expect(assistant.timeline[0], isA<ThoughtTimelineEntry>());
      expect(
        (assistant.timeline[0] as ThoughtTimelineEntry).text,
        '大思考第一段：先看代码结构',
      );
      expect(assistant.timeline[1], isA<ToolTimelineEntry>());
      expect((assistant.timeline[1] as ToolTimelineEntry).toolCallId, 'tc-read');
      expect(assistant.timeline[2], isA<ThoughtTimelineEntry>());
      expect(
        (assistant.timeline[2] as ThoughtTimelineEntry).text,
        '小思考：定位到需要修改的位置',
      );
      expect(assistant.timeline[3], isA<ToolTimelineEntry>());
      expect((assistant.timeline[3] as ToolTimelineEntry).toolCallId, 'tc-edit');
      expect(assistant.timeline[4], isA<MessageTimelineEntry>());
      expect(
        (assistant.timeline[4] as MessageTimelineEntry).text,
        '已经帮你完成了修改。',
      );

      // Directly constructed items without explicit timeline still synthesize cleanly.
      final legacy = AssistantTranscriptItem(
        id: 'legacy-1',
        timestamp: DateTime(2026),
        thought: 'legacy thought',
        text: 'legacy reply',
        toolCalls: const [
          AcpToolCall(toolCallId: 'tc-old', title: 'read'),
        ],
      );
      expect(legacy.effectiveTimeline.length, 3);
      expect(legacy.effectiveTimeline[0], isA<ThoughtTimelineEntry>());
      expect(legacy.effectiveTimeline[1], isA<ToolTimelineEntry>());
      expect(legacy.effectiveTimeline[2], isA<MessageTimelineEntry>());
    });
  });
}
