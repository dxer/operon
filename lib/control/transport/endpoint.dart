import 'dart:convert';
import 'dart:io';

import '../protocol/errors.dart';
import 'devtools_socket.dart';

/// One attachable page, as the DevTools `/json/list` endpoint reports it.
class CdpTarget {
  const CdpTarget({
    required this.id,
    required this.type,
    required this.title,
    required this.url,
    required this.path,
  });

  final String id;

  /// `page`, `iframe`, `worker`, …
  final String type;
  final String title;
  final String url;

  /// The WebSocket path to use on the DevTools socket, e.g. `/devtools/page/ABC`.
  final String path;

  bool get isPage => type == 'page';

  @override
  String toString() => 'CdpTarget($type, $url)';
}

/// Opens one connection to the DevTools server.
///
/// A function rather than a host and a port: production connects over the
/// WebView's abstract Unix socket, and a test connects over a loopback TCP
/// server. Everything above this line — the HTTP exchange, the WebSocket
/// upgrade, JSON-RPC — is then exercised for real in both.
typedef SocketConnector = Future<Socket> Function();

/// Lists the targets the DevTools server can see.
Future<List<CdpTarget>> listTargets({
  required SocketConnector connect,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final socket = await connect();
  final raw = await httpGetOverSocket(socket, '/json/list', timeout: timeout);

  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException catch (error) {
    throw ControlException(
      ControlErrorCode.captureFailed,
      '/json/list 返回了无法解析的内容：$error',
      details: {'body': raw.length > 200 ? raw.substring(0, 200) : raw},
    );
  }
  if (decoded is! List) {
    throw const ControlException(
      ControlErrorCode.captureFailed,
      '/json/list 返回了意外的内容',
    );
  }
  return decoded.whereType<Map<String, Object?>>().map((entry) {
    final wsUrl = entry['webSocketDebuggerUrl'] as String? ?? '';
    final path = wsUrl.isEmpty ? '' : Uri.parse(wsUrl).path;
    return CdpTarget(
      id: entry['id'] as String? ?? '',
      type: entry['type'] as String? ?? '',
      title: entry['title'] as String? ?? '',
      url: entry['url'] as String? ?? '',
      path: path.isEmpty ? '/devtools/page/${entry['id']}' : path,
    );
  }).toList(growable: false);
}
