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
  });

  group('SshAcpConnection helpers', () {
    test('quotes custom agy path safely', () {
      expect(
        SshAcpConnection.buildRemoteAcpCommand("/opt/my'bin/agy"),
        contains("exec '/opt/my'\\''bin/agy' acp"),
      );
    });
  });
}
