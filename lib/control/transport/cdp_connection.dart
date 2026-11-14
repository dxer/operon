import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../protocol/errors.dart';
import 'websocket.dart';

/// A CDP event, possibly from a child session.
class CdpEvent {
  const CdpEvent({required this.method, this.params = const {}, this.sessionId});

  final String method;
  final Map<String, Object?> params;
  final String? sessionId;

  @override
  String toString() => 'CdpEvent($method, session: $sessionId)';
}

/// JSON-RPC over the target's WebSocket: one request id, one response.
///
/// Nothing here knows about pages, refs or tools; it correlates ids, keeps
/// events flowing and turns protocol errors into typed failures.
class CdpConnection {
  CdpConnection(this._socket) {
    _subscription = _socket.messages.listen(
      _onData,
      onError: (Object error) => _failAll(
        ControlException(
          ControlErrorCode.channelUnavailable,
          '调试通道断开：$error',
          hint: '页面可能被关闭或刷新；重新附加后再试',
        ),
      ),
      onDone: () => _failAll(
        const ControlException(
          ControlErrorCode.targetMissing,
          '调试通道已关闭',
          hint: '页面可能被关闭或刷新；重新附加后再试',
        ),
      ),
      cancelOnError: true,
    );
  }

  /// Opens a session to one target.
  static Future<CdpConnection> open({
    required Future<Socket> Function() connect,
    required String path,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final socket = await CdpWebSocket.connect(connect, path, timeout: timeout);
    return CdpConnection(socket);
  }

  final CdpWebSocket _socket;
  late final StreamSubscription<String> _subscription;
  final Map<int, Completer<Map<String, Object?>>> _pending = {};
  final StreamController<CdpEvent> _events = StreamController<CdpEvent>.broadcast();
  int _nextId = 1;
  bool _closed = false;

  Stream<CdpEvent> get events => _events.stream;

  bool get isClosed => _closed;

  int get pendingCount => _pending.length;

  /// Sends one command and waits for its response.
  ///
  /// [sessionId] targets a child frame session; CDP's flattened mode carries
  /// it on the same socket.
  Future<Map<String, Object?>> send(
    String method, {
    Map<String, Object?>? params,
    String? sessionId,
    Duration timeout = const Duration(seconds: 20),
  }) {
    if (_closed) {
      return Future.error(
        ControlException(
          ControlErrorCode.targetMissing,
          '调试通道已关闭，无法发送 $method',
        ),
      );
    }
    final id = _nextId++;
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    try {
      _socket.send(jsonEncode({
        'id': id,
        'method': method,
        if (params != null && params.isNotEmpty) 'params': params,
        if (sessionId != null) 'sessionId': sessionId,
      }));
    } catch (error) {
      _pending.remove(id);
      return Future.error(
        ControlException(
          ControlErrorCode.channelUnavailable,
          '无法向调试通道写入 $method：$error',
        ),
      );
    }
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(id);
        throw ControlException(
          ControlErrorCode.timeout,
          '$method 超时（${timeout.inSeconds}s 无响应）',
          details: {'method': method},
        );
      },
    );
  }

  /// Sends a command and forgets the response, for setup calls whose failure
  /// only costs an "unsupported" later.
  void sendNoWait(String method, {Map<String, Object?>? params, String? sessionId}) {
    if (_closed) return;
    try {
      _socket.send(jsonEncode({
        'id': _nextId++,
        'method': method,
        if (params != null && params.isNotEmpty) 'params': params,
        if (sessionId != null) 'sessionId': sessionId,
      }));
    } catch (_) {
      // Nothing to do: a dropped setup message is not a failed tool call.
    }
  }

  void _onData(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return;
    }
    if (decoded is! Map<String, Object?>) return;

    final id = (decoded['id'] as num?)?.toInt();
    if (id != null) {
      final completer = _pending.remove(id);
      if (completer == null || completer.isCompleted) return;
      final error = decoded['error'];
      if (error is Map<String, Object?>) {
        completer.completeError(_mapError(error, decoded['method'] as String?));
      } else {
        final result = decoded['result'];
        completer.complete(
          result is Map<String, Object?> ? result : const <String, Object?>{},
        );
      }
      return;
    }

    final method = decoded['method'] as String?;
    if (method == null) return;
    final params = decoded['params'];
    if (!_events.isClosed) {
      _events.add(CdpEvent(
        method: method,
        params: params is Map<String, Object?> ? params : const {},
        sessionId: decoded['sessionId'] as String?,
      ));
    }
  }

  /// CDP error codes are unhelpful on their own; the message carries the
  /// meaning, so the mapping keys on it.
  ControlException _mapError(Map<String, Object?> error, String? method) {
    final message = error['message'] as String? ?? '未知协议错误';
    final code = (error['code'] as num?)?.toInt();
    final details = <String, Object?>{
      if (method != null) 'method': method,
      if (code != null) 'cdpCode': code,
    };
    if (message.contains('does not belong to the document') ||
        message.contains('No node with given id') ||
        message.contains('Could not find node with given id') ||
        message.contains('Node is detached')) {
      return ControlException(
        ControlErrorCode.staleRef,
        '页面已变化，之前看到的元素不再有效',
        hint: '重新取一次页面快照，用新的 ref 操作',
        details: details,
      );
    }
    if (message.contains('was not found') || message.contains('Cannot find context')) {
      if (code == -32601 || message.contains("wasn't found")) {
        return ControlException(
          ControlErrorCode.unsupported,
          '当前 WebView 不支持该调试能力：$message',
          hint: '系统 WebView 版本可能过旧，更新 Android System WebView 后重试',
          details: details,
        );
      }
      return ControlException(
        ControlErrorCode.notFound,
        '目标不存在：$message',
        details: details,
      );
    }
    if (code == -32601) {
      return ControlException(
        ControlErrorCode.unsupported,
        '当前 WebView 不支持该调试能力：$message',
        hint: '系统 WebView 版本可能过旧，更新 Android System WebView 后重试',
        details: details,
      );
    }
    return ControlException(
      ControlErrorCode.internal,
      message,
      details: details,
    );
  }

  void _failAll(ControlException error) {
    if (_closed) return;
    _closed = true;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pending.clear();
    _subscription.cancel();
    if (!_events.isClosed) _events.close();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          const ControlException(ControlErrorCode.targetMissing, '调试通道已关闭'),
        );
      }
    }
    _pending.clear();
    if (!_events.isClosed) await _events.close();
    await _subscription.cancel();
    await _socket.close();
  }
}
