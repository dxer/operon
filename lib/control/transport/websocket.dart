import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../protocol/errors.dart';

/// A WebSocket client over a socket this code opens itself.
///
/// `WebSocket.connect` cannot be used: it opens its own TCP connection, and the
/// WebView's DevTools server listens on an abstract Unix socket. The socket is
/// therefore opened by the caller and the HTTP upgrade written here.
/// `WebSocket.fromUpgradedSocket` cannot be used either, because reading the
/// upgrade response subscribes to the socket, and it refuses one that was
/// already listened to.
///
/// So the framing lives here: text frames in both directions, the control frames
/// a server sends (ping/pong/close), and a masked client. CDP never negotiates
/// compression, so permessage-deflate is neither offered nor expected.
class CdpWebSocket {
  CdpWebSocket._(this._socket);

  /// Opens a connection and upgrades it to a WebSocket.
  ///
  /// [connect] opens the transport: the WebView's abstract Unix socket in the
  /// app, a loopback TCP server in a test. The upgrade is written by hand
  /// because `WebSocket.connect` opens its own TCP connection, which cannot
  /// reach an abstract Unix socket.
  static Future<CdpWebSocket> connect(
    Future<Socket> Function() connect,
    String path, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final socket = await connect();
    final client = CdpWebSocket._(socket);
    try {
      await client._upgrade(path, timeout);
      return client;
    } catch (_) {
      socket.destroy();
      rethrow;
    }
  }

  final Socket _socket;
  final List<int> _buffer = [];
  final List<int> _header = [];
  final List<int> _fragment = [];
  final StreamController<String> _messages = StreamController<String>();
  final Completer<void> _upgraded = Completer<void>();
  late final StreamSubscription<Uint8List> _subscription;
  bool _closed = false;

  /// Text messages from the other end.
  Stream<String> get messages => _messages.stream;

  bool get isClosed => _closed;

  Future<void> _upgrade(String path, Duration timeout) async {
    final key = base64Encode(List<int>.generate(16, (_) => Random.secure().nextInt(256)));
    _socket.write(
      'GET $path HTTP/1.1\r\n'
      'Host: localhost\r\n'
      'Upgrade: websocket\r\n'
      'Connection: Upgrade\r\n'
      'Sec-WebSocket-Key: $key\r\n'
      'Sec-WebSocket-Version: 13\r\n'
      '\r\n',
    );
    await _socket.flush();

    _subscription = _socket.listen(
      _onData,
      onError: (Object error) {
        if (!_upgraded.isCompleted) {
          _upgraded.completeError(
            ControlException(ControlErrorCode.channelUnavailable, '调试通道断开：$error'),
          );
        }
        _finish();
      },
      onDone: () {
        if (!_upgraded.isCompleted) {
          _upgraded.completeError(
            const ControlException(ControlErrorCode.channelUnavailable, '调试通道在握手时关闭'),
          );
        }
        _finish();
      },
      cancelOnError: true,
    );

    await _upgraded.future.timeout(
      timeout,
      onTimeout: () => throw const ControlException(
        ControlErrorCode.timeout,
        '等待调试通道握手超时',
      ),
    );
  }

  void _onData(Uint8List chunk) {
    if (!_upgraded.isCompleted) {
      _header.addAll(chunk);
      final end = _indexOfHeaderEnd(_header);
      if (end < 0) return;
      final head = latin1.decode(_header.sublist(0, end));
      final firstLine = head.split('\r\n').first;
      final rest = _header.sublist(end + 4);
      _header.clear();
      if (!firstLine.contains(' 101')) {
        _upgraded.completeError(ControlException(
          ControlErrorCode.targetMissing,
          'WebSocket 握手被拒绝：$firstLine',
          hint: '该页面可能已被另一个调试客户端占用',
        ));
        _finish();
        return;
      }
      _upgraded.complete();
      if (rest.isNotEmpty) _parse(rest);
      return;
    }
    _parse(chunk);
  }

  /// Reads whole frames out of [_buffer] and keeps the incomplete tail.
  void _parse(List<int> bytes) {
    _buffer.addAll(bytes);
    while (true) {
      if (_buffer.length < 2) return;
      final first = _buffer[0];
      final second = _buffer[1];
      final fin = (first & 0x80) != 0;
      final opcode = first & 0x0f;
      final masked = (second & 0x80) != 0;
      var length = second & 0x7f;
      var offset = 2;

      if (length == 126) {
        if (_buffer.length < 4) return;
        length = (_buffer[2] << 8) | _buffer[3];
        offset = 4;
      } else if (length == 127) {
        if (_buffer.length < 10) return;
        length = 0;
        for (var index = 2; index < 10; index++) {
          length = (length << 8) | _buffer[index];
        }
        offset = 10;
      }

      var maskKey = const <int>[];
      if (masked) {
        if (_buffer.length < offset + 4) return;
        maskKey = _buffer.sublist(offset, offset + 4);
        offset += 4;
      }
      if (_buffer.length < offset + length) return;

      var payload = _buffer.sublist(offset, offset + length);
      _buffer.removeRange(0, offset + length);
      if (masked) {
        payload = [
          for (var index = 0; index < payload.length; index++)
            payload[index] ^ maskKey[index % 4],
        ];
      }

      switch (opcode) {
        case 0x0:
          _fragment.addAll(payload);
          if (fin) _emitFragment();
        case 0x1:
        case 0x2:
          if (fin) {
            _fragment.clear();
            _emit(payload);
          } else {
            _fragment
              ..clear()
              ..addAll(payload);
          }
        case 0x8:
          _finish();
          return;
        case 0x9:
          _sendFrame(0xA, payload);
        case 0xA:
          break;
        default:
          // Reserved opcodes are ignored rather than treated as a bad message.
          break;
      }
    }
  }

  void _emitFragment() {
    if (_fragment.isEmpty) return;
    final payload = List<int>.from(_fragment);
    _fragment.clear();
    _emit(payload);
  }

  void _emit(List<int> payload) {
    if (_messages.isClosed) return;
    _messages.add(utf8.decode(payload, allowMalformed: true));
  }

  /// Sends one text message as a single masked frame.
  void send(String text) {
    if (_closed) {
      throw const ControlException(
        ControlErrorCode.targetMissing,
        '调试通道已关闭',
      );
    }
    _sendFrame(0x1, utf8.encode(text));
  }

  void _sendFrame(int opcode, List<int> payload) {
    if (_closed) return;
    final header = <int>[0x80 | opcode];
    if (payload.length < 126) {
      header.add(0x80 | payload.length);
    } else if (payload.length < 65536) {
      header
        ..add(0x80 | 126)
        ..add((payload.length >> 8) & 0xff)
        ..add(payload.length & 0xff);
    } else {
      header.add(0x80 | 127);
      for (var shift = 7; shift >= 0; shift--) {
        header.add((payload.length >> (8 * shift)) & 0xff);
      }
    }
    final mask = List<int>.generate(4, (_) => Random.secure().nextInt(256));
    header.addAll(mask);
    final masked = Uint8List(payload.length);
    for (var index = 0; index < payload.length; index++) {
      masked[index] = payload[index] ^ mask[index % 4];
    }
    try {
      _socket.add(header);
      _socket.add(masked);
    } catch (_) {
      _finish();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _sendFrame(0x8, const []);
    _finish();
    await _subscription.cancel();
    await _socket.close();
  }

  void _finish() {
    if (_closed) return;
    _closed = true;
    if (!_messages.isClosed) _messages.close();
    _socket.destroy();
  }

  static int _indexOfHeaderEnd(List<int> bytes) {
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
}
