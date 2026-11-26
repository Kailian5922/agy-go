import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:acp_client/acp_client.dart';
import 'package:agy_remote/agy_remote.dart';
import 'package:test/test.dart';

void main() {
  group('LoopbackAcpTransport', () {
    test('authenticates with session token and exchanges ACP JSON-RPC frames', () async {
      const expectedToken = 'test-secret-token-123';
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      unawaited(
        server.first.then((socket) {
          var authed = false;
          socket
              .cast<List<int>>()
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen((line) {
                final msg = jsonDecode(line) as Map<String, dynamic>;
                if (!authed) {
                  if (msg['auth'] == expectedToken) {
                    authed = true;
                    socket.writeln(jsonEncode({'ok': true}));
                  } else {
                    socket.writeln(jsonEncode({'ok': false, 'error': 'unauthorized'}));
                    socket.destroy();
                  }
                  return;
                }
                if (msg['method'] == 'initialize') {
                  socket.writeln(
                    jsonEncode({
                      'jsonrpc': '2.0',
                      'id': msg['id'],
                      'result': {
                        'protocolVersion': 1,
                        'agentInfo': {'name': 'agy-local', 'version': '1.5.17'},
                        'agentCapabilities': {'loadSession': true},
                      },
                    }),
                  );
                }
              });
        }),
      );

      final transport = await LoopbackAcpTransport.connect(
        port: server.port,
        token: expectedToken,
      );
      final client = AcpClient(transport);
      final init = await client.initialize();
      expect(init.agentInfo?.name, 'agy-local');
      expect(init.capabilities.loadSession, isTrue);

      await client.close();
    });

    test('rejects invalid bridge token fail-closed', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      unawaited(
        server.first.then((socket) {
          socket
              .cast<List<int>>()
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen((_) {
                socket.writeln(jsonEncode({'ok': false, 'error': 'bad token'}));
                socket.destroy();
              });
        }),
      );

      await expectLater(
        LoopbackAcpTransport.connect(port: server.port, token: 'wrong'),
        throwsA(isA<AcpTransportException>()),
      );
    });

    test('serializes concurrent RPC writes (closeSession + loadSession) without StreamSink errors', () async {
      const token = 'concurrent-test-token';
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      final receivedMethods = <String>[];
      unawaited(
        server.first.then((socket) {
          var authed = false;
          socket
              .cast<List<int>>()
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen((line) {
                final msg = jsonDecode(line) as Map<String, dynamic>;
                if (!authed) {
                  authed = msg['auth'] == token;
                  socket.writeln(jsonEncode({'ok': authed}));
                  return;
                }
                final method = msg['method'] as String;
                receivedMethods.add(method);
                final result = switch (method) {
                  'initialize' => {
                    'protocolVersion': 1,
                    'agentCapabilities': {
                      'loadSession': true,
                      'sessionCapabilities': {'close': {}, 'list': {}},
                    },
                  },
                  'session/load' => {'sessionId': (msg['params'] as Map)['sessionId']},
                  'session/list' => {'sessions': const <Object?>[]},
                  _ => <String, Object?>{},
                };
                socket.writeln(
                  jsonEncode({
                    'jsonrpc': '2.0',
                    'id': msg['id'],
                    'result': result,
                  }),
                );
              });
        }),
      );

      final transport = await LoopbackAcpTransport.connect(
        port: server.port,
        token: token,
      );
      final client = AcpClient(transport);
      addTearDown(client.close);

      await client.initialize();

      // Reproduce switching from a new chat (closing draft) to a previous chat (loading history)
      // plus listing sessions all in the exact same event-loop turn.
      final results = await Future.wait<Object?>([
        client.closeSession('draft-1').then((_) => 'closed'),
        client.loadSession(sessionId: 'old-session-1', cwd: '/tmp'),
        client.listSessions(),
      ]);

      expect(results[0], 'closed');
      expect((results[1] as AcpSessionHandle).sessionId, 'old-session-1');
      expect(receivedMethods, ['initialize', 'session/close', 'session/load', 'session/list']);
    });
  });

  group('SshAcpConnection helpers', () {
    test('quotes custom agy path safely', () {
      expect(
        SshAcpConnection.buildRemoteAcpCommand("/opt/my'bin/agy"),
        contains("exec '/opt/my'\\''bin/agy' acp"),
      );
    });

    test('builds non-interactive remote quota command with updater disabled', () {
      final cmd = SshAcpConnection.buildRemoteQuotaCommand("/opt/my'bin/agy");
      expect(cmd, contains('AGY_CLI_DISABLE_AUTO_UPDATE=true'));
      expect(cmd, contains('NO_BROWSER=1'));
      expect(cmd, contains("'/opt/my'\\''bin/agy' -p /usage --output-format json </dev/null"));
    });
  });
}
