import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:operon/control/protocol/errors.dart';
import 'package:operon/control/transport/devtools_socket.dart';

void main() {
  group('DevToolsAddress', () {
    test('is the abstract socket Chromium names after the process', () {
      final address = defaultDevToolsAddress();
      expect(address.name, '@webview_devtools_remote_$pid');
      expect(address.pid, pid);
      // An abstract socket has no filesystem path; the "@" is what makes Dart
      // treat the name as one.
      expect(address.name.startsWith('@'), isTrue);
    });
  });

  group('dechunk', () {
    test('joins a chunked body', () {
      const body =
          '4\r\nWiki\r\n5\r\npedia\r\n0\r\n\r\n';
      expect(utf8.decode(dechunk(utf8.encode(body))), 'Wikipedia');
    });

    test('handles a chunk size line with an extension', () {
      const body = '4;foo=bar\r\nWiki\r\n0\r\n\r\n';
      expect(utf8.decode(dechunk(utf8.encode(body))), 'Wiki');
    });

    test('an empty body is empty', () {
      expect(dechunk(utf8.encode('0\r\n\r\n')), isEmpty);
    });
  });

  group('httpGetOverSocket', () {
    late HttpServer server;
    late int port;

    setUpAll(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      port = server.port;
      server.listen((request) async {
        if (request.uri.path != '/json/list') {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode([
          {'id': 'T1', 'type': 'page', 'url': 'https://example.com/'},
        ]));
        await request.response.close();
      });
    });

    tearDownAll(() => server.close(force: true));

    test('reads a body the server streams as chunked', () async {
      final socket = await Socket.connect('127.0.0.1', port);
      final body = await httpGetOverSocket(socket, '/json/list');
      final decoded = jsonDecode(body) as List;
      expect(decoded.single['id'], 'T1');
    });

    test('a non-200 answer is a typed failure, not an empty list', () async {
      final socket = await Socket.connect('127.0.0.1', port);
      await expectLater(
        httpGetOverSocket(socket, '/missing'),
        throwsA(isA<ControlException>().having(
          (error) => error.code,
          'code',
          ControlErrorCode.captureFailed,
        )),
      );
    });
  });

  group('discovery', () {
    test('an address that cannot be reached reports where it looked', () async {
      // Port 0 on a name nothing listens on: the failure must name the socket,
      // because that is the one fact the user can act on.
      const address = DevToolsAddress(name: '@operon_nonexistent_test', pid: 0);
      await expectLater(
        connectDevTools(address, timeout: const Duration(seconds: 1)),
        throwsA(isA<ControlException>().having(
          (error) => error.message,
          'message',
          contains('@operon_nonexistent_test'),
        )),
      );
    });
  });
}
