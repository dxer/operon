import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../protocol/errors.dart';

/// Where a WebView's DevTools server is listening.
///
/// Android's WebView starts a DevTools server inside the app process whenever
/// `setWebContentsDebuggingEnabled(true)` has run, on the abstract Unix socket
/// `@webview_devtools_remote_<pid>`. It is an abstract socket — it has no path
/// on the filesystem — and Dart has supported those on Android since 2.9, so the
/// whole transport stays in Dart: no platform channel, no byte relay, nothing
/// native to compile.
class DevToolsAddress {
  const DevToolsAddress({required this.name, required this.pid});

  /// The abstract socket name, including the leading `@`.
  final String name;
  final int pid;

  /// The value a DevTools HTTP `Host` header should carry.
  static const String host = 'localhost';

  String get uri => 'unix:$name';

  @override
  String toString() => '$name (pid $pid)';
}

/// The name the WebView's DevTools server uses in this process.
///
/// Deterministic: Chromium names it after the pid that created the WebView, and
/// this app runs its WebViews in the main process, which is the process Dart
/// runs in too.
DevToolsAddress defaultDevToolsAddress() =>
    DevToolsAddress(name: '@webview_devtools_remote_$pid', pid: pid);

/// Finds the socket, preferring the name this process must own.
///
/// `/proc/net/unix` is consulted only as a fallback: some Android builds hide it
/// from apps, and the computed name is the one that will be right in practice.
Future<DevToolsAddress> findDevToolsAddress({bool verify = true}) async {
  final own = defaultDevToolsAddress();
  if (!verify) return own;
  if (await _canConnect(own)) return own;

  final fromProc = await _scanProcNetUnix();
  if (fromProc != null && await _canConnect(fromProc)) return fromProc;

  throw ControlException(
    ControlErrorCode.channelUnavailable,
    '找不到 WebView 调试通道（${own.name}）',
    hint: '先打开任意网页再试；若仍失败，可能是系统 WebView 版本过旧，'
        '或该设备的 WebView 没有为这个进程开启 DevTools',
  );
}

/// Opens a connection to the DevTools server.
///
/// Every CDP connection — the HTTP discovery request and each page's WebSocket —
/// gets its own socket, which is what the server expects.
Future<Socket> connectDevTools(
  DevToolsAddress address, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  try {
    return await Socket.connect(
      InternetAddress(address.name, type: InternetAddressType.unix),
      0,
      timeout: timeout,
    );
  } on SocketException catch (error) {
    throw ControlException(
      ControlErrorCode.channelUnavailable,
      '无法连接 WebView 调试通道（${address.name}）：${error.osError?.message ?? error.message}',
      hint: '先打开任意网页再试，并确认设置里没有禁用 WebView 调试',
    );
  }
}

Future<bool> _canConnect(DevToolsAddress address) async {
  try {
    final socket = await connectDevTools(address, timeout: const Duration(seconds: 2));
    socket.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

/// Reads `/proc/net/unix` for a `webview_devtools_remote_<pid>` row.
Future<DevToolsAddress?> _scanProcNetUnix() async {
  try {
    final lines = await File('/proc/net/unix').readAsLines();
    for (final line in lines) {
      final name = line.split(' ').last.trim();
      if (name.isEmpty) continue;
      final bare = name.startsWith('@') ? name.substring(1) : name;
      if (!bare.startsWith('webview_devtools_remote_')) continue;
      final suffix = bare.substring('webview_devtools_remote_'.length);
      final pid = int.tryParse(suffix);
      return DevToolsAddress(name: '@$bare', pid: pid ?? 0);
    }
  } catch (_) {
    // Hidden by SELinux or absent: the computed name is the real fallback.
  }
  return null;
}

/// Reads a whole HTTP/1.1 response from a socket and returns its body.
///
/// Used for `/json/*`, the only HTTP the DevTools server speaks. Both framings
/// are handled because a WebView's server streams the target list as chunked.
Future<String> httpGetOverSocket(
  Socket socket,
  String path, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  try {
    socket.write(
      'GET $path HTTP/1.1\r\n'
      'Host: ${DevToolsAddress.host}\r\n'
      'Connection: close\r\n'
      '\r\n',
    );
    await socket.flush();
    final bytes = <int>[];
    await socket.listen(bytes.addAll).asFuture<void>().timeout(timeout, onTimeout: () {});
    final split = _indexOfHeaderEnd(bytes);
    if (split < 0) {
      throw const ControlException(
        ControlErrorCode.captureFailed,
        '调试通道返回的响应不完整',
      );
    }
    final head = latin1.decode(bytes.sublist(0, split)).toLowerCase();
    if (!head.startsWith('http/1.1 200') && !head.startsWith('http/1.0 200')) {
      final firstLine = latin1.decode(bytes.sublist(0, split)).split('\r\n').first;
      throw ControlException(
        ControlErrorCode.captureFailed,
        '调试通道拒绝了 $path：$firstLine',
      );
    }
    final body = bytes.sublist(split + 4);
    if (head.contains('transfer-encoding: chunked')) {
      return utf8.decode(dechunk(body), allowMalformed: true);
    }
    return utf8.decode(body, allowMalformed: true);
  } finally {
    socket.destroy();
  }
}

/// Joins a `Transfer-Encoding: chunked` body back into bytes.
List<int> dechunk(List<int> body) {
  final payload = <int>[];
  var offset = 0;
  while (offset < body.length) {
    var lineEnd = offset;
    while (lineEnd + 1 < body.length &&
        !(body[lineEnd] == 13 && body[lineEnd + 1] == 10)) {
      lineEnd++;
    }
    if (lineEnd + 1 >= body.length) break;
    final sizeText = latin1.decode(body.sublist(offset, lineEnd)).split(';').first.trim();
    final size = int.tryParse(sizeText, radix: 16);
    if (size == null || size == 0) break;
    final start = lineEnd + 2;
    if (start + size > body.length) break;
    payload.addAll(body.sublist(start, start + size));
    offset = start + size + 2;
  }
  return payload;
}

int _indexOfHeaderEnd(List<int> bytes) {
  for (var index = 0; index + 3 < bytes.length; index++) {
    if (bytes[index] == 13 &&
        bytes[index + 1] == 10 &&
        bytes[index + 2] == 13 &&
        bytes[index + 3] == 10) {
      return index;
    }
  }
  return -1;
}
