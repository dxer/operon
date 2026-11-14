import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:operon/control/protocol/errors.dart';
import 'package:operon/control/transport/cdp_connection.dart';
import 'package:operon/control/transport/endpoint.dart';

/// A stand-in for the WebView's DevTools server, on the host.
///
/// The relay in the app forwards bytes untouched, so everything above the socket
/// (HTTP discovery, the WebSocket upgrade, JSON-RPC correlation) is exercised
/// here for real rather than against a mock.
void main() {
  late HttpServer server;
  late int port;
  final received = <Map<String, Object?>>[];

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server.port;
    server.listen((request) async {
      if (request.uri.path == '/json/list') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode([
          {
            'id': 'T1',
            'type': 'page',
            'title': '示例页',
            'url': 'https://example.com/',
            'webSocketDebuggerUrl': 'ws://localhost:9222/devtools/page/T1',
          },
          {
            'id': 'W1',
            'type': 'service_worker',
            'title': 'worker',
            'url': 'https://example.com/sw.js',
            'webSocketDebuggerUrl': 'ws://localhost:9222/devtools/page/W1',
          },
        ]));
        await request.response.close();
        return;
      }
      if (!WebSocketTransformer.isUpgradeRequest(request)) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen((data) {
        final message = jsonDecode('$data') as Map<String, Object?>;
        received.add(message);
        final id = message['id'];
        switch (message['method']) {
          case 'bogus.method':
            socket.add(jsonEncode({
              'id': id,
              'error': {'code': -32601, 'message': "bogus.method wasn't found"},
            }));
          case 'Node.stale':
            socket.add(jsonEncode({
              'id': id,
              'error': {
                'code': -32000,
                'message': 'Node with given id does not belong to the document',
              },
            }));
          case 'Slow.method':
            // Deliberately unanswered: the caller's timeout has to cover it.
            break;
          case 'Page.navigate':
            socket.add(jsonEncode({
              'id': id,
              'result': {'frameId': 'F1'},
            }));
            socket.add(jsonEncode({
              'method': 'Page.frameNavigated',
              'params': {
                'frame': {'id': 'F1', 'url': 'https://example.com/next'},
              },
            }));
          default:
            socket.add(jsonEncode({
              'id': id,
              'result': {
                'echo': message['method'],
                if (message.containsKey('sessionId')) 'session': message['sessionId'],
              },
            }));
        }
      });
    });
  });

  tearDownAll(() async => server.close(force: true));

  setUp(received.clear);

  group('discovery', () {
    test('lists targets and keeps only the page', () async {
      final targets = await listTargets(
        connect: () => Socket.connect('127.0.0.1', port),
      );
      expect(targets, hasLength(2));
      final pages = targets.where((target) => target.isPage).toList();
      expect(pages, hasLength(1));
      expect(pages.single.url, 'https://example.com/');
      expect(pages.single.path, '/devtools/page/T1');
    });
  });

  group('CdpConnection', () {
    test('correlates a response and carries the child session id', () async {
      final connection = await CdpConnection.open(
        connect: () => Socket.connect('127.0.0.1', port),
        path: '/devtools/page/T1',
      );
      addTearDown(connection.close);

      final result = await connection.send(
        'Accessibility.getFullAXTree',
        sessionId: 'S1',
      );

      expect(result['echo'], 'Accessibility.getFullAXTree');
      expect(result['session'], 'S1');
      expect(received.single['sessionId'], 'S1');
    });

    test('events arrive on their own stream', () async {
      final connection = await CdpConnection.open(
        connect: () => Socket.connect('127.0.0.1', port),
        path: '/devtools/page/T1',
      );
      addTearDown(connection.close);

      final event = connection.events.firstWhere(
        (event) => event.method == 'Page.frameNavigated',
      );
      await connection.send('Page.navigate', params: {'url': 'https://example.com/next'});
      final frameNavigated = await event.timeout(const Duration(seconds: 2));

      expect(frameNavigated.params['frame'], isA<Map>());
    });

    test('a detached node becomes staleRef, so the caller re-observes', () async {
      final connection = await CdpConnection.open(
        connect: () => Socket.connect('127.0.0.1', port),
        path: '/devtools/page/T1',
      );
      addTearDown(connection.close);

      await expectLater(
        connection.send('Node.stale'),
        throwsA(isA<ControlException>().having(
          (error) => error.code,
          'code',
          ControlErrorCode.staleRef,
        )),
      );
    });

    test('an unknown method becomes unsupported', () async {
      final connection = await CdpConnection.open(
        connect: () => Socket.connect('127.0.0.1', port),
        path: '/devtools/page/T1',
      );
      addTearDown(connection.close);

      await expectLater(
        connection.send('bogus.method'),
        throwsA(isA<ControlException>().having(
          (error) => error.code,
          'code',
          ControlErrorCode.unsupported,
        )),
      );
    });

    test('a closed connection fails instead of hanging', () async {
      final connection = await CdpConnection.open(
        connect: () => Socket.connect('127.0.0.1', port),
        path: '/devtools/page/T1',
      );
      await connection.close();

      await expectLater(
        connection.send('Runtime.evaluate'),
        throwsA(isA<ControlException>().having(
          (error) => error.code,
          'code',
          ControlErrorCode.targetMissing,
        )),
      );
    });

    test('a request with no answer times out instead of waiting forever', () async {
      final connection = await CdpConnection.open(
        connect: () => Socket.connect('127.0.0.1', port),
        path: '/devtools/page/T1',
      );
      addTearDown(connection.close);

      await expectLater(
        connection.send('Slow.method', timeout: const Duration(milliseconds: 120)),
        throwsA(isA<ControlException>().having(
          (error) => error.code,
          'code',
          ControlErrorCode.timeout,
        )),
      );
    });
  });
}
