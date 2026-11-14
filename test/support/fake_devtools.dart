import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A stand-in for the WebView's DevTools server, good enough to drive the whole
/// control layer on a machine with no Android device.
///
/// It speaks the two things the layer needs: `/json/list` over HTTP, and JSON-RPC
/// over a WebSocket. Everything above the transport — the accessibility outline,
/// refs, geometry, actionability, the diff, receipts — runs unchanged, so a
/// scenario written here fails for the same reasons it would fail on a phone.
///
/// The page is data, not a browser: [nodes] is the accessibility tree, a click
/// only has an effect the scenario gives it, and nothing is laid out or painted.
class FakePageNode {
  const FakePageNode({
    required this.backendNodeId,
    required this.role,
    required this.name,
    this.value,
    this.disabled = false,
    this.editable = false,
    this.checked,
    this.focused = false,
  });

  final int backendNodeId;
  final String role;
  final String name;
  final String? value;
  final bool disabled;
  final bool editable;
  final bool? checked;
  final bool focused;

  Map<String, Object?> toAxJson(String parentId) => {
        'nodeId': 'n$backendNodeId',
        'parentId': parentId,
        'backendDOMNodeId': backendNodeId,
        'role': {'type': 'role', 'value': role},
        'name': {'type': 'computedString', 'value': name},
        if (value != null) 'value': {'type': 'string', 'value': value},
        'properties': [
          if (disabled) {'name': 'disabled', 'value': {'type': 'boolean', 'value': true}},
          if (editable) {'name': 'editable', 'value': {'type': 'boolean', 'value': true}},
          if (checked != null)
            {'name': 'checked', 'value': {'type': 'booleanOrUndefined', 'value': checked}},
          if (focused) {'name': 'focused', 'value': {'type': 'boolean', 'value': true}},
        ],
      };
}

/// A rectangle a node occupies, in CSS pixels.
class FakeBox {
  const FakeBox(this.left, this.top, this.width, this.height);

  final double left;
  final double top;
  final double width;
  final double height;

  List<double> get quad => [left, top, left + width, top, left + width, top + height, left, top + height];
}

class FakeDevTools {
  FakeDevTools._(this._server, this.pages);

  final HttpServer _server;

  /// One entry per open tab. The first is the default `page`.
  final List<FakePage> pages;

  FakePage get page => pages.first;

  /// Which page a socket is driving: each target has its own WebSocket path.
  final Map<Socket, FakePage> _socketPage = {};

  /// Every CDP method the layer called, in order. Assertions read this.
  final List<String> methods = [];

  /// Node ids the layer asked to scroll into view, in order.
  final List<int> scrolledIntoView = [];

  /// Sessions attached with `flatten: true`, so a frame test can prove the layer
  /// reads them.
  final List<String> childSessions = [];

  /// What to answer for one method, when the default is not enough.
  final Map<String, Object? Function(Map<String, Object?> params)> overrides = {};

  static Future<FakeDevTools> start(FakePage page, {List<FakePage> also = const []}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeDevTools._(server, [page, ...also]);
    server.listen((request) => unawaited(fake._serve(request)));
    return fake;
  }

  int get port => _server.port;

  /// A connector the layer can use instead of the WebView's unix socket.
  Future<Socket> connect() => Socket.connect('127.0.0.1', port);

  Future<void> close() => _server.close(force: true);

  int countOf(String method) => methods.where((name) => name == method).length;

  // --- HTTP ---------------------------------------------------------------

  Future<void> _serve(HttpRequest request) async {
    final path = request.uri.path;
    if (path.startsWith('/devtools/')) {
      final socket = await request.response.detachSocket(writeHeaders: false);
      final id = path.split('/').last;
      _socketPage[socket] =
          pages.where((candidate) => candidate.id == id).firstOrNull ?? page;
      _webSocket(request, socket);
      return;
    }
    if (path == '/json/list') {
      final body = jsonEncode([
        for (final page in pages)
          {
            'id': page.id,
            'type': 'page',
            'title': page.title,
            'url': page.url,
            'webSocketDebuggerUrl': 'ws://localhost:${_server.port}/devtools/page/${page.id}',
          },
      ]);
      request.response.headers.set('Transfer-Encoding', 'chunked');
      request.response.headers.contentType = ContentType.json;
      // Written in two chunks on purpose: the layer has to de-chunk a body the
      // real server also streams.
      request.response.add(utf8.encode(body.substring(0, body.length ~/ 2)));
      request.response.add(utf8.encode(body.substring(body.length ~/ 2)));
      await request.response.close();
      return;
    }
    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  }

  // --- WebSocket ----------------------------------------------------------

  void _webSocket(HttpRequest request, Socket socket) {
    socket.write(
      'HTTP/1.1 101 Switching Protocols\r\n'
      'Upgrade: websocket\r\n'
      'Connection: Upgrade\r\n'
      'Sec-WebSocket-Accept: fake\r\n'
      '\r\n',
    );
    final frames = _FrameReader(socket, (text) => _onMessage(text, socket));
    socket.listen(frames.add, onDone: frames.close, onError: (_) => frames.close());
  }

  void _onMessage(String text, Socket socket) {
    final Map<String, Object?> message;
    try {
      message = (jsonDecode(text) as Map).cast<String, Object?>();
    } catch (_) {
      return;
    }
    final id = message['id'];
    if (id == null) return;
    final method = message['method'] as String? ?? '';
    final params = (message['params'] as Map?)?.cast<String, Object?>() ?? const {};
    final sessionId = message['sessionId'] as String?;
    methods.add(method);
    final answer = _answer(
      method,
      params,
      sessionId,
      _socketPage[socket] ?? page,
      socket,
    );
    _send(socket, {
      'id': id,
      'result': answer ?? const <String, Object?>{},
      if (sessionId != null) 'sessionId': sessionId,
    });
  }

  Object? _answer(
    String method,
    Map<String, Object?> params,
    String? sessionId,
    FakePage page,
    Socket socket,
  ) {
    final override = overrides[method];
    if (override != null) return override(params);
    switch (method) {
      case 'Page.getNavigationHistory':
        return {
          'currentIndex': page.historyIndex,
          'entries': [
            for (var i = 0; i < page.history.length; i++)
              {'id': i + 1, 'url': page.history[i], 'title': page.title},
          ],
        };
      case 'Page.navigate':
        page.history.add(params['url']?.toString() ?? '');
        page.historyIndex = page.history.length - 1;
        page.url = params['url']?.toString() ?? page.url;
        page.scrollY = 0;
        _announceLoad(page, socket);
        return const <String, Object?>{};
      case 'Page.navigateToHistoryEntry':
        final entryId = (params['entryId'] as num?)?.toInt() ?? 0;
        final index = entryId - 1;
        if (index < 0 || index >= page.history.length) {
          return const {'errorText': 'no such entry'};
        }
        page.historyIndex = index;
        page.url = page.history[index];
        page.scrollY = 0;
        _announceLoad(page, socket);
        return const <String, Object?>{};
      case 'DOM.scrollIntoViewIfNeeded':
        final nodeId = (params['backendNodeId'] as num?)?.toInt() ?? -1;
        scrolledIntoView.add(nodeId);
        final box = page.boxOf(nodeId);
        if (box != null) page.scrollY = (box.top - 40).clamp(0, double.infinity);
        return const <String, Object?>{};
      case 'DOM.setFileInputFiles':
        final nodeId = (params['backendNodeId'] as num?)?.toInt() ?? -1;
        final files = (params['files'] as List?)?.whereType<String>().toList() ?? const [];
        page.uploadedFiles[nodeId] = files;
        return const <String, Object?>{};
      case 'Accessibility.getFullAXTree':
        final nodes = page.nodesFor(sessionId);
        // Each document gets its own node ids: two roots called n0 would make
        // one frame's nodes overwrite the other's in the outline.
        final rootId = sessionId == null ? 'n0' : 'n0-$sessionId';
        return {
          'nodes': [
            _rootJson(sessionId, rootId),
            for (final node in nodes) node.toAxJson(rootId),
          ],
        };
      case 'DOM.getContentQuads':
        final id = (params['backendNodeId'] as num?)?.toInt() ?? 0;
        final box = page.boxOf(id);
        if (box == null) return const {'quads': <Object?>[]};
        return {
          'quads': [box.quad],
        };
      case 'DOM.getNodeForLocation':
        final id = page.nodeAt(
          (params['x'] as num?)?.toDouble() ?? 0,
          (params['y'] as num?)?.toDouble() ?? 0,
        );
        return {if (id != null) 'backendNodeId': id};
      case 'DOM.describeNode':
        final id = (params['backendNodeId'] as num?)?.toInt() ?? 0;
        return {
          'node': {'backendNodeId': id, 'children': const <Object?>[]},
        };
      case 'DOM.resolveNode':
        final id = (params['backendNodeId'] as num?)?.toInt() ?? 0;
        return {
          'object': {'objectId': 'obj-$id', 'type': 'object'},
        };
      case 'Runtime.callFunctionOn':
        final value = page.callOnNode(
          (params['objectId'] as String? ?? '').replaceFirst('obj-', ''),
          params['functionDeclaration'] as String? ?? '',
          ((params['arguments'] as List?) ?? const [])
              .whereType<Map>()
              .map((arg) => arg['value'])
              .toList(),
        );
        return {
          'result': {'type': 'object', 'value': value},
        };
      case 'Runtime.releaseObject':
        return const <String, Object?>{};
      case 'Page.getLayoutMetrics':
        return {
          'cssLayoutViewport': {
            'clientWidth': 400,
            'clientHeight': 800,
            'pageX': 0,
            'pageY': page.scrollY,
          },
          'cssContentSize': {'x': 0, 'y': 0, 'width': 400, 'height': page.contentHeight},
        };
      case 'Page.captureScreenshot':
        return {'data': base64Encode(utf8.encode('fake-png'))};
      case 'Target.setAutoAttach':
        if (params['autoAttach'] == true) {
          // A frame appears after auto-attach, the way a payment iframe would.
          final id = page.childSessionId;
          if (id != null) {
            scheduleMicrotask(() => _send(socket, {
                  'method': 'Target.attachedToTarget',
                  'params': {
                    'sessionId': id,
                    'targetInfo': {'type': 'iframe', 'targetId': 'frame-$id'},
                    'waitingForDebugger': true,
                  },
                }));
          }
        }
        return const <String, Object?>{};
      case 'Page.enable':
        if (page.dialogOpen) {
          scheduleMicrotask(() => _send(socket, {
                'method': 'Page.javascriptDialogOpening',
                'params': {'type': 'confirm', 'message': '确定要离开吗？'},
              }));
        }
        return const <String, Object?>{};
      case 'Page.handleJavaScriptDialog':
        page.dialogOpen = false;
        return const <String, Object?>{};
      case 'Input.insertText':
        page.typedText.add(params['text']?.toString() ?? '');
        return const <String, Object?>{};
      case 'Input.dispatchMouseEvent':
      case 'Input.dispatchTouchEvent':
      case 'Input.dispatchKeyEvent':
        page.receiveInput(method, params);
        return const <String, Object?>{};
      default:
        // Everything else (Page.enable, DOM.enable, Runtime.enable, …) only has
        // to not fail: the layer treats an empty result as success.
        return const <String, Object?>{};
    }
  }

  Map<String, Object?> _rootJson(String? sessionId, String nodeId) => {
        'nodeId': nodeId,
        'role': {'type': 'role', 'value': 'RootWebArea'},
        'name': {'type': 'computedString', 'value': page.title},
        'backendDOMNodeId': 0,
        'childIds': [for (final node in page.nodesFor(sessionId)) 'n${node.backendNodeId}'],
      };

  /// A document finished loading, the way the browser reports it. Without this
  /// the layer waits out its navigation budget on every page change.
  void _announceLoad(FakePage page, Socket socket) {
    scheduleMicrotask(() {
      _send(socket, {
        'method': 'Page.frameNavigated',
        'params': {
          'frame': {'id': 'main', 'url': page.url},
        },
      });
      _send(socket, {'method': 'Page.loadEventFired', 'params': {'timestamp': 0}});
    });
  }

  void _send(Socket? socket, Map<String, Object?> message) {
    final payload = utf8.encode(jsonEncode(message));
    final header = <int>[0x81];
    if (payload.length < 126) {
      header.add(payload.length);
    } else if (payload.length < 65536) {
      header..add(126)..addAll([payload.length >> 8 & 0xFF, payload.length & 0xFF]);
    } else {
      header.add(127);
      for (var shift = 56; shift >= 0; shift -= 8) {
        header.add(payload.length >> shift & 0xFF);
      }
    }
    socket?.add(header..addAll(payload));
  }
}

/// What the fake page is: its address, its tree, and what an action does.
class FakePage {
  FakePage({
    required this.url,
    this.id = 'T1',
    this.title = '测试页面',
    List<FakePageNode> nodes = const [],
    this.childSessionId,
    this.contentHeight = 1600,
    List<String>? history,
  })  : nodes = List.of(nodes),
        history = history ?? [url],
        historyIndex = (history ?? const []).length - 1;

  /// The DevTools target id. Distinct tabs have distinct ids.
  final String id;

  String url;
  String title;

  /// Session history the way the browser keeps it: going back restores an entry
  /// instead of navigating to an address again.
  final List<String> history;
  int historyIndex;

  /// How far the page is scrolled, in CSS pixels.
  double scrollY = 0;

  /// backendNodeId → the file paths handed to that input.
  final Map<int, List<String>> uploadedFiles = {};
  List<FakePageNode> nodes;
  /// A child frame the page will report after `Target.setAutoAttach`.
  String? childSessionId;
  final double contentHeight;

  /// Nodes of a child frame, keyed by session id. Empty means "same as main".
  final Map<String, List<FakePageNode>> frameNodes = {};

  bool dialogOpen = false;
  final List<String> typedText = [];

  /// Where each node sits. Missing means "not rendered".
  final Map<int, FakeBox> boxes = {};

  /// What clicking a node does. Default: nothing.
  void Function(FakePageNode node)? onClick;

  /// Nodes to serve for one session.
  List<FakePageNode> nodesFor(String? sessionId) {
    if (sessionId == null) return nodes;
    return frameNodes[sessionId] ?? const [];
  }

  FakeBox? boxOf(int backendNodeId) => boxes[backendNodeId];


  /// The topmost node at a viewport point: the last box drawn wins, which is how
  /// a page-wide overlay ends up covering the button underneath it.
  ///
  /// Boxes are in document coordinates and DevTools asks in viewport ones, so
  /// the current scroll offset is added back in.
  int? nodeAt(double x, double y) {
    final contentY = y + scrollY;
    int? best;
    for (final entry in boxes.entries) {
      final box = entry.value;
      if (x < box.left || x > box.left + box.width) continue;
      if (contentY < box.top || contentY > box.top + box.height) continue;
      best = entry.key;
    }
    return best;
  }

  void receiveInput(String method, Map<String, Object?> params) {
    if (method == 'Input.dispatchKeyEvent') {
      final key = params['key']?.toString();
      if (key == 'a' || key == 'A') typedText.clear();
      return;
    }
    final type = params['type']?.toString() ?? '';
    // One press is one click: touchStart / mousePressed. The move and the end
    // are part of the same gesture and must not fire the handler again.
    if (type != 'touchStart' && type != 'mousePressed') return;
    final x = (params['x'] as num?)?.toDouble() ?? 0;
    final y = (params['y'] as num?)?.toDouble() ?? 0;
    final id = nodeAt(x, y);
    if (id == null) return;
    final node = nodes.where((n) => n.backendNodeId == id).firstOrNull;
    if (node != null) onClick?.call(node);
  }

  /// Answers the two `<select>` functions the layer calls on a node.
  Map<String, Object?> callOnNode(String backendId, String function, List<Object?> args) {
    final id = int.tryParse(backendId) ?? -1;
    if (function.contains("type === 'file'")) {
      final isFile = fileInputs.contains(id);
      return {
        'isFile': isFile,
        'tag': isFile ? 'INPUT' : 'DIV',
        'count': uploadedFiles[id]?.length ?? 0,
        'accept': '',
      };
    }
    if (function.contains('el.selectedIndex = index')) {
      final select = selects[id];
      final index = (args.isEmpty ? null : args.first as num?)?.toInt();
      if (select == null || index == null || index < 0 || index >= select.length) {
        return const {};
      }
      selectedIndex[id] = index;
      return {'value': select[index].value, 'label': select[index].label};
    }
    if (function.contains('options')) {
      final select = selects[id];
      if (select == null) return const {'isSelect': false, 'tag': 'DIV'};
      return {
        'isSelect': true,
        'options': [
          for (var i = 0; i < select.length; i++)
            {'index': i, 'value': select[i].value, 'label': select[i].label, 'disabled': select[i].disabled},
        ],
      };
    }
    return const {};
  }

  /// Nodes that are `<input type=file>`.
  final Set<int> fileInputs = {};

  /// Node id → its options, for the nodes that are native selects.
  final Map<int, List<FakeSelectOption>> selects = {};

  /// Node id → the index a script set. Assertions read this.
  final Map<int, int> selectedIndex = {};
}

class FakeSelectOption {
  const FakeSelectOption(this.value, this.label, {this.disabled = false});

  final String value;
  final String label;
  final bool disabled;
}

/// Reads client frames (masked) and hands back their text payloads.
class _FrameReader {
  _FrameReader(this._socket, this._onText);

  final Socket _socket;
  final void Function(String text) _onText;
  final List<int> _buffer = [];

  void add(List<int> bytes) {
    _buffer.addAll(bytes);
    _drain();
  }

  void _drain() {
    while (true) {
      if (_buffer.length < 2) return;
      final opcode = _buffer[0] & 0x0F;
      final masked = (_buffer[1] & 0x80) != 0;
      var length = _buffer[1] & 0x7F;
      var offset = 2;
      if (length == 126) {
        if (_buffer.length < 4) return;
        length = (_buffer[2] << 8) | _buffer[3];
        offset = 4;
      } else if (length == 127) {
        if (_buffer.length < 10) return;
        length = 0;
        for (var i = 0; i < 8; i++) {
          length = (length << 8) | _buffer[2 + i];
        }
        offset = 10;
      }
      final maskOffset = offset;
      if (masked) offset += 4;
      if (_buffer.length < offset + length) return;
      final payload = Uint8List.fromList(_buffer.sublist(offset, offset + length));
      if (masked) {
        for (var i = 0; i < payload.length; i++) {
          payload[i] ^= _buffer[maskOffset + (i % 4)];
        }
      }
      _buffer.removeRange(0, offset + length);
      if (opcode == 0x8) {
        _socket.destroy();
        return;
      }
      if (opcode == 0x1 || opcode == 0x2) _onText(utf8.decode(payload, allowMalformed: true));
      // Continuation and control frames are not produced by this client.
    }
  }

  void close() {}
}
