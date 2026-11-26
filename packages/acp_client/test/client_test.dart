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
  });
}
