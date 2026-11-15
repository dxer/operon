import 'dart:async';
import 'dart:io';

import 'interaction/geometry.dart';
import 'interaction/input.dart';
import 'perception/ax.dart';
import 'perception/captcha.dart';
import 'perception/diff.dart';
import 'perception/find.dart';
import 'perception/options.dart';
import 'perception/outline.dart';
import 'protocol/errors.dart';
import 'protocol/gesture.dart';
import 'protocol/results.dart';
import 'refs.dart';
import 'transport/cdp_connection.dart';
import 'transport/devtools_socket.dart';
import 'transport/endpoint.dart';

part 'session_geometry.dart';

/// A run's handle on one page.
///
/// Everything the agent does goes through here: it observes, it acts, and it
/// reports what happened. It holds no model and no prompt, so the same session
/// serves the agent and the flow runner.
/// One element's box in viewport coordinates, and whether that point is on
/// screen. Outside the viewport is not a target: an event there reaches nothing
/// and still looks delivered, so the box and the verdict travel together.
typedef MeasuredBox = ({
  double x,
  double y,
  double left,
  double top,
  double width,
  double height,
  bool inViewport,
});

class ControlSession {
  ControlSession._(this._connection, this._target);

  /// Attaches to a page.
  ///
  /// [urlHint] picks the tab when the app has several WebViews open: each one
  /// is its own target, and attaching to the wrong one would act on a page the
  /// user is not looking at.
  /// [connect] replaces the transport. Tests use it to run the whole layer
  /// against a fake DevTools server; production never passes it.
  static Future<ControlSession> attach({
    DevToolsAddress? address,
    SocketConnector? connect,
    String? urlHint,
    String? targetId,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final devtools = connect == null ? (address ?? await findDevToolsAddress()) : null;
    Future<Socket> open() =>
        connect != null ? connect() : connectDevTools(devtools!, timeout: timeout);
    final targets = await listTargets(connect: open);
    final pages = targets.where((target) => target.isPage).toList();
    if (pages.isEmpty) {
      throw const ControlException(
        ControlErrorCode.targetMissing,
        '没有找到可附加的页面',
        hint: '先打开一个网页，页面加载完成后再执行任务',
      );
    }
    final target = _chooseTarget(pages, urlHint, targetId);
    final connection = await CdpConnection.open(
      connect: open,
      path: target.path,
      timeout: timeout,
    );
    final session = ControlSession._(connection, target);
    await session._prepare();
    return session;
  }

  /// Every page the DevTools server can see.
  ///
  /// Read from the same socket the session uses, so what it lists is what the
  /// app actually has open — not what a previous snapshot remembered.
  static Future<List<CdpTarget>> listTabs({
    DevToolsAddress? address,
    SocketConnector? connect,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final devtools = connect == null ? (address ?? await findDevToolsAddress()) : null;
    Future<Socket> open() =>
        connect != null ? connect() : connectDevTools(devtools!, timeout: timeout);
    final targets = await listTargets(connect: open, timeout: timeout);
    return targets.where((target) => target.isPage).toList(growable: false);
  }

  static CdpTarget _chooseTarget(
    List<CdpTarget> pages,
    String? urlHint,
    String? targetId,
  ) {
    if (targetId != null && targetId.isNotEmpty) {
      for (final page in pages) {
        if (page.id == targetId) return page;
      }
      throw ControlException(
        ControlErrorCode.targetMissing,
        '找不到标签页 $targetId',
        hint: '先用 tabs 看当前打开了哪些标签页',
      );
    }
    if (urlHint != null && urlHint.isNotEmpty) {
      for (final page in pages) {
        if (page.url == urlHint) return page;
      }
      for (final page in pages) {
        if (page.url.isNotEmpty && urlHint.startsWith(_origin(page.url))) return page;
      }
    }
    // About:blank targets appear before a WebView navigates; they are never
    // what the user means.
    for (final page in pages) {
      if (page.url.isNotEmpty && !page.url.startsWith('about:')) return page;
    }
    return pages.first;
  }

  static String _origin(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return url;
    return '${uri.scheme}://${uri.host}';
  }

  final CdpConnection _connection;
  final CdpTarget _target;
  final RefRegistry _refs = RefRegistry();
  final Map<String, String> _childSessions = {};
  final List<String> _notes = [];

  /// Notified before an input is dispatched, with the point and the box it
  /// lands on.
  ///
  /// The UI uses this to move the ghost cursor and outline the element. The
  /// layer decides both, so the animation can never claim a place the click did
  /// not go.
  void Function(GestureTarget target)? onGesture;

  StreamSubscription<CdpEvent>? _events;
  List<String> _lastLines = const [];
  String? _lastUrl;
  bool _dialogOpen = false;
  CaptchaInfo _captcha = CaptchaInfo.none;

  /// How a click reaches the page. The default follows the page.
  InputMode inputMode = InputMode.auto;

  CdpConnection get connection => _connection;

  RefRegistry get refs => _refs;

  CdpTarget get target => _target;

  bool get isAttached => !_connection.isClosed;

  /// How many child frames currently have their own session.
  int get childSessionCount => _childSessions.length;

  /// What the last capture saw of a human-verification challenge.
  ///
  /// The layer reports it and never tries to solve it: a challenge is the
  /// user's step in every mode.
  CaptchaInfo get captcha => _captcha;

  /// Anything the capture could not show, kept for the caller's report.
  List<String> get notes => List.unmodifiable(_notes);

  Future<void> _prepare() async {
    _events = _connection.events.listen(_onEvent);
    await _connection.send('Page.enable');
    await _connection.send('DOM.enable');
    await _connection.send('Runtime.enable');
    try {
      await _connection.send('Accessibility.enable');
    } on ControlException catch (error) {
      throw ControlException(
        ControlErrorCode.unsupported,
        '当前 WebView 无法读取无障碍树：${error.message}',
        hint: '更新 Android System WebView 后重试',
      );
    }
    // Child frames get their own sessions, so an embedded payment or login form
    // can be read and acted on like the main document.
    try {
      await _connection.send('Target.setAutoAttach', params: {
        'autoAttach': true,
        'waitForDebuggerOnStart': true,
        'flatten': true,
      });
    } on ControlException {
      // Not fatal: without it the session only sees the main frame.
      _notes.add('无法附加子 frame，iframe 内的内容不可见');
    }
    _lastUrl = await currentUrl();
  }

  void _onEvent(CdpEvent event) {
    switch (event.method) {
      case 'Page.frameNavigated':
        final frame = event.params['frame'];
        if (frame is Map && frame['parentId'] == null) {
          // A new document: every ref the caller holds is now a guess.
          _refs.beginDocument();
          _lastLines = const [];
          _lastUrl = frame['url'] as String?;
        }
      case 'Page.javascriptDialogOpening':
        _dialogOpen = true;
      case 'Page.javascriptDialogClosed':
        _dialogOpen = false;
      case 'Target.attachedToTarget':
        final sessionId = event.params['sessionId'] as String?;
        final info = event.params['targetInfo'];
        if (sessionId != null && info is Map && info['type'] == 'iframe') {
          _childSessions[sessionId] = info['targetId'] as String? ?? sessionId;
          unawaited(_prepareChildSession(sessionId));
        }
      case 'Target.detachedFromTarget':
        final sessionId = event.params['sessionId'] as String?;
        if (sessionId != null) _childSessions.remove(sessionId);
    }
  }

  Future<void> _prepareChildSession(String sessionId) async {
    try {
      await _connection.send('Page.enable', sessionId: sessionId);
      await _connection.send('DOM.enable', sessionId: sessionId);
      await _connection.send('Accessibility.enable', sessionId: sessionId);
      await _connection.send('Runtime.runIfWaitingForDebugger', sessionId: sessionId);
    } on ControlException {
      _notes.add('子 frame 初始化失败，其内容不可见');
    }
  }

  /// Reads the page and hands back an outline whose refs are the only ones the
  /// caller may use.
  Future<Outline> snapshot({bool includeContent = true}) async {
    final url = await currentUrl();
    final nodes = await _captureAxNodes();
    if (nodes.isEmpty) {
      throw const ControlException(
        ControlErrorCode.captureFailed,
        '页面没有任何可读取的内容',
        hint: '页面可能还在加载，稍后重试或先等待页面稳定',
      );
    }
    _captcha = detectCaptcha(nodes);
    final title = _titleOf(nodes) ?? _target.title;
    final outline = OutlineBuilder().build(
      nodes: nodes,
      refs: _refs,
      url: url,
      title: title,
    );
    _lastLines = List.of(outline.lines);
    _lastUrl = url;
    return outline;
  }

  Future<List<AxNode>> _captureAxNodes() async {
    final nodes = <AxNode>[];
    nodes.addAll(await _captureSession(null));
    for (final sessionId in _childSessions.keys.toList()) {
      try {
        nodes.addAll(await _captureSession(sessionId));
      } on ControlException {
        _note('iframe 内容读取失败');
      }
    }
    return nodes;
  }

  Future<List<AxNode>> _captureSession(String? sessionId) async {
    final result = await _connection.send(
      'Accessibility.getFullAXTree',
      sessionId: sessionId,
    );
    final parsed = parseAxNodes(result['nodes']);
    if (sessionId == null) return parsed;
    // Tag the session so an action knows where to be sent.
    return [
      for (final node in parsed)
        AxNode(
          nodeId: node.nodeId,
          role: node.role,
          parentId: node.parentId,
          childIds: node.childIds,
          name: node.name,
          value: node.value,
          ignored: node.ignored,
          backendNodeId: node.backendNodeId,
          properties: node.properties,
          sessionId: sessionId,
        ),
    ];
  }

  String? _titleOf(List<AxNode> nodes) {
    for (final node in nodes) {
      if (node.role == 'RootWebArea' || node.role == 'WebArea') {
        final name = node.name.trim();
        if (name.isNotEmpty) return name;
      }
    }
    return null;
  }

  /// The page's current address, read from the session rather than script.
  Future<String> currentUrl() async {
    try {
      final history = await _connection.send('Page.getNavigationHistory');
      final entries = history['entries'];
      final index = (history['currentIndex'] as num?)?.toInt() ?? 0;
      if (entries is List && index >= 0 && index < entries.length) {
        final entry = entries[index];
        if (entry is Map) {
          final url = entry['url'] as String?;
          if (url != null && url.isNotEmpty) return url;
        }
      }
    } on ControlException {
      // Fall through to the target's last known address.
    }
    return _lastUrl ?? _target.url;
  }

  /// Clicks the element behind [ref].
  ///
  /// The point is computed, checked and dispatched in that order: nothing is
  /// re-tried after the event leaves, and a covered target fails instead of
  /// clicking whatever is on top of it.
  Future<Receipt> click(String ref, {InputMode? mode}) async {
    final started = DateTime.now();
    _ensureUsable();
    final record = _refs.lookup(ref);
    final point = await _actionablePoint(record);
    _announceGesture(record, point);
    final urlBefore = await currentUrl();
    final linesBefore = _lastLines;
    await tapAt(
      _connection,
      x: point.x,
      y: point.y,
      mode: mode ?? inputMode,
      sessionId: record.sessionId,
    );
    final observed = await _settleAndObserve(urlBefore, linesBefore);
    return Receipt(
      tool: 'click',
      delivery: Delivery.delivered,
      pageReacted: observed.changed,
      changes: observed.changes,
      urlBefore: urlBefore,
      urlAfter: observed.url,
      elapsed: DateTime.now().difference(started),
      details: {
        'ref': ref,
        'role': record.role,
        'x': point.x,
        'y': point.y,
        'mode': (mode ?? inputMode).name,
        if (record.sessionId != null) 'frame': record.sessionId,
      },
    );
  }

  /// Types into the element behind [ref].
  ///
  /// [replace] clears the field first. The text goes through the browser's
  /// editing pipeline, so a controlled input's framework state updates.
  Future<Receipt> type(
    String ref,
    String text, {
    bool replace = false,
    bool submit = false,
    bool secret = false,
    InputMode? mode,
  }) async {
    final started = DateTime.now();
    _ensureUsable();
    final record = _refs.lookup(ref);
    if (record.role == 'Iframe') {
      throw const ControlException(
        ControlErrorCode.notEditable,
        'iframe 本身不能输入文字',
        hint: '先读取 iframe 内部的输入框，用它的 ref 输入',
      );
    }
    if (!record.editable) {
      throw ControlException(
        ControlErrorCode.notEditable,
        '元素 [${record.ref}] 不接受文字输入（${record.role}）',
        hint: '先 snapshot，用其中的输入框 ref；需要点击的用 click',
        details: {'ref': record.ref, 'role': record.role},
      );
    }
    final point = await _actionablePoint(record);
    _announceGesture(record, point);
    final urlBefore = await currentUrl();
    final linesBefore = _lastLines;

    await tapAt(
      _connection,
      x: point.x,
      y: point.y,
      mode: mode ?? inputMode,
      sessionId: record.sessionId,
    );
    if (replace) {
      await selectAll(_connection, sessionId: record.sessionId);
    }
    await insertText(_connection, text, sessionId: record.sessionId);
    if (submit) {
      await pressKey(
        _connection,
        keySpecFor('Enter')!,
        sessionId: record.sessionId,
      );
    }
    final observed = await _settleAndObserve(
      urlBefore,
      linesBefore,
      waitForNavigation: submit,
    );
    return Receipt(
      tool: submit ? 'type+submit' : 'type',
      delivery: Delivery.delivered,
      pageReacted: observed.changed,
      changes: observed.changes,
      urlBefore: urlBefore,
      urlAfter: observed.url,
      elapsed: DateTime.now().difference(started),
      note: secret ? '输入的是敏感内容，未记录正文' : null,
      details: {
        'ref': ref,
        'role': record.role,
        'chars': text.length,
        if (!secret) 'text': text,
        if (replace) 'replace': true,
        if (submit) 'submit': true,
      },
    );
  }

  /// Moves the pointer over the element behind [ref] and leaves it there.
  ///
  /// Needed where a menu only opens on hover. The pointer is not moved again
  /// afterwards: the next click at another point would close it, which is why
  /// this exists as a tool of its own instead of a side effect of click.
  Future<Receipt> hover(String ref) async {
    final started = DateTime.now();
    _ensureUsable();
    final record = _refs.lookup(ref);
    final point = await _actionablePoint(record);
    _announceGesture(record, point);
    final urlBefore = await currentUrl();
    final linesBefore = _lastLines;
    await hoverAt(
      _connection,
      x: point.x,
      y: point.y,
      sessionId: record.sessionId,
    );
    final observed = await _settleAndObserve(urlBefore, linesBefore);
    return Receipt(
      tool: 'hover',
      delivery: Delivery.delivered,
      pageReacted: observed.changed,
      changes: observed.changes,
      urlBefore: urlBefore,
      urlAfter: observed.url,
      elapsed: DateTime.now().difference(started),
      note: observed.changed ? null : '悬停后页面没有变化，这可能是普通链接',
      details: {'ref': ref, 'role': record.role, 'x': point.x, 'y': point.y},
    );
  }

  /// Chooses an option in a native `<select>`.
  ///
  /// A native dropdown paints a system-owned popup that no input event can
  /// reach, so the option is set on the element and `input`/`change` are
  /// dispatched — the same route every browser automation tool takes. That is
  /// different from a click, and the receipt says so instead of reporting a
  /// delivery that never happened.
  Future<Receipt> select(
    String ref, {
    String? label,
    String? value,
    int? index,
  }) async {
    final started = DateTime.now();
    _ensureUsable();
    if (label == null && value == null && index == null) {
      throw const ControlException(
        ControlErrorCode.badArguments,
        'select 需要一个挑选依据：optionLabel、optionValue 或 optionIndex',
      );
    }
    final record = _refs.lookup(ref);
    final urlBefore = await currentUrl();
    final linesBefore = _lastLines;

    final shape = await _callOnRef(record, _describeSelectJs);
    if (shape['isSelect'] != true) {
      throw ControlException(
        ControlErrorCode.notEditable,
        '元素 [${record.ref}] 不是原生下拉框（${shape['tag'] ?? record.role}）',
        hint: '这是自定义下拉：先 click 展开它，再从快照里点选具体选项',
        details: {'ref': record.ref, 'role': record.role, 'tag': shape['tag']},
      );
    }
    final options = [
      for (final item in (shape['options'] as List? ?? const []))
        if (item is Map) SelectOption.fromJson(item.cast<String, Object?>()),
    ];
    final choice = chooseOption(options, label: label, value: value, index: index);
    final applied = await _callOnRef(record, _applySelectJs, [choice.option.index]);

    final observed = await _settleAndObserve(urlBefore, linesBefore);
    final after = applied['value']?.toString();
    return Receipt(
      tool: 'select',
      delivery: Delivery.unknown,
      pageReacted: observed.changed,
      expectedStateReached: after == choice.option.value,
      changes: observed.changes,
      urlBefore: urlBefore,
      urlAfter: observed.url,
      elapsed: DateTime.now().difference(started),
      note: '原生下拉由脚本设置选中项（系统弹层无法用鼠标事件驱动）',
      details: {
        'ref': ref,
        'role': record.role,
        'matchedBy': choice.how,
        'label': choice.option.label,
        'value': choice.option.value,
        'index': choice.option.index,
        'optionCount': options.length,
        'selectionAfter': after,
      },
    );
  }

  /// Calls a function on the node behind [ref] and returns its value.
  ///
  /// `this` inside [body] is the element. Only used where an input event cannot
  /// express the intent (`<select>`): everything else goes through real input.
  Future<Map<String, Object?>> _callOnRef(
    RefRecord record,
    String body, [
    List<Object?> args = const [],
  ]) async {
    final resolved = await _connection.send(
      'DOM.resolveNode',
      params: {'backendNodeId': record.backendNodeId},
      sessionId: record.sessionId,
    );
    final objectId = (resolved['object'] as Map?)?['objectId'] as String?;
    if (objectId == null || objectId.isEmpty) {
      throw ControlException(
        ControlErrorCode.staleRef,
        '元素 [${record.ref}] 已不在这个文档里',
        hint: '重新 snapshot 再试',
      );
    }
    try {
      final result = await _connection.send(
        'Runtime.callFunctionOn',
        params: {
          'objectId': objectId,
          'functionDeclaration': body,
          'arguments': [
            for (final arg in args) {'value': arg},
          ],
          'returnByValue': true,
        },
        sessionId: record.sessionId,
      );
      final value = (result['result'] as Map?)?['value'];
      if (value is Map) return value.cast<String, Object?>();
      return const {};
    } on ControlException catch (error) {
      throw ControlException(
        ControlErrorCode.captureFailed,
        '读取元素 [${record.ref}] 失败：${error.message}',
        hint: '重新 snapshot 再试',
      );
    } finally {
      try {
        await _connection.send(
          'Runtime.releaseObject',
          params: {'objectId': objectId},
          sessionId: record.sessionId,
        );
      } catch (_) {
        // Releasing is housekeeping; a closed connection has nothing to leak.
      }
    }
  }

  /// Reads a `<select>`'s options without changing anything.
  static const String _describeSelectJs = '''function() {
    const el = this;
    if (!(el instanceof HTMLSelectElement)) {
      return { isSelect: false, tag: el.tagName || '', role: el.getAttribute('role') || '' };
    }
    return {
      isSelect: true,
      multiple: !!el.multiple,
      disabled: !!el.disabled,
      options: Array.prototype.map.call(el.options, function (o, i) {
        return { index: i, value: o.value, label: (o.text || '').trim(), disabled: !!o.disabled };
      }),
    };
  }''';

  /// Sets the selected index and lets the page's own handlers run.
  static const String _applySelectJs = '''function(index) {
    const el = this;
    el.selectedIndex = index;
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
    const chosen = el.options[el.selectedIndex];
    return { value: el.value, label: chosen ? (chosen.text || '').trim() : '' };
  }''';

  /// Presses one key in the focused element.
  Future<Receipt> press(String key, {int modifiers = 0}) async {
    final started = DateTime.now();
    _ensureUsable();
    final spec = keySpecFor(key);
    if (spec == null) {
      throw ControlException(
        ControlErrorCode.unsupported,
        '不支持按键 $key',
        hint: '支持：${_keyNames.join('、')}',
      );
    }
    final urlBefore = await currentUrl();
    final linesBefore = _lastLines;
    await pressKey(_connection, spec, modifiers: modifiers);
    final observed = await _settleAndObserve(urlBefore, linesBefore);
    return Receipt(
      tool: 'press',
      delivery: Delivery.delivered,
      pageReacted: observed.changed,
      changes: observed.changes,
      urlBefore: urlBefore,
      urlAfter: observed.url,
      elapsed: DateTime.now().difference(started),
      details: {'key': key},
    );
  }

  /// Scrolls the page from the middle of the viewport.
  Future<Receipt> scroll({
    String direction = 'down',
    int? amount,
    String? ref,
  }) async {
    final started = DateTime.now();
    _ensureUsable();
    final urlBefore = await currentUrl();
    final linesBefore = _lastLines;
    final viewport = await _viewport();
    final distance = (amount ?? (viewport.height * 0.8)).toDouble();
    final sign = direction == 'up' ? -1 : 1;
    double x = viewport.width / 2;
    double y = viewport.height / 2;
    if (ref != null) {
      // Scrolling at the element's own point moves the list that contains it,
      // not the page.
      final record = _refs.lookup(ref);
      final point = await _viewportPoint(record);
      x = point.x;
      y = point.y;
    }
    await wheelAt(_connection, x: x, y: y, deltaY: distance * sign);
    final observed = await _settleAndObserve(urlBefore, linesBefore);
    return Receipt(
      tool: 'scroll',
      delivery: Delivery.delivered,
      pageReacted: observed.changed,
      changes: observed.changes,
      urlBefore: urlBefore,
      urlAfter: observed.url,
      elapsed: DateTime.now().difference(started),
      details: {'direction': direction, 'distance': distance.round()},
    );
  }

  /// Opens [url] and waits for the document to load.
  Future<Receipt> navigate(String url) async {
    final started = DateTime.now();
    _ensureUsable();
    final urlBefore = await currentUrl();
    final loaded = _connection.events
        .firstWhere((event) => event.method == 'Page.loadEventFired')
        .timeout(const Duration(seconds: 20), onTimeout: () => const CdpEvent(method: 'Page.loadEventFired'));
    final result = await _connection.send('Page.navigate', params: {'url': url});
    final errorText = result['errorText'] as String?;
    if (errorText != null && errorText.isNotEmpty) {
      throw ControlException(
        ControlErrorCode.navigation,
        '无法打开 $url：$errorText',
        details: {'url': url},
      );
    }
    try {
      await loaded;
    } on TimeoutException {
      _note('等待页面加载超时，继续读取当前内容');
    }
    final observed = await _settleAndObserve(
      urlBefore,
      const [],
      waitForNavigation: false,
      settleMs: 300,
    );
    _refs.beginDocument();
    return Receipt(
      tool: 'navigate',
      delivery: Delivery.delivered,
      pageReacted: urlBefore != observed.url || observed.changed,
      urlBefore: urlBefore,
      urlAfter: observed.url,
      elapsed: DateTime.now().difference(started),
      details: {'url': url},
    );
  }

  /// Waits for a ref to appear, for a duration, or for the page to settle.
  Future<Receipt> wait({String? ref, int? ms, Duration? timeout}) async {
    final started = DateTime.now();
    _ensureUsable();
    final budget = timeout ?? const Duration(seconds: 8);
    if (ms != null && ref == null) {
      final capped = ms.clamp(0, 10000);
      await Future<void>.delayed(Duration(milliseconds: capped));
      return Receipt(
        tool: 'wait',
        delivery: Delivery.notDelivered,
        elapsed: DateTime.now().difference(started),
        details: {'ms': capped},
      );
    }
    if (ref == null) {
      await _settle();
      return Receipt(
        tool: 'wait',
        delivery: Delivery.notDelivered,
        pageReacted: true,
        elapsed: DateTime.now().difference(started),
      );
    }
    final deadline = DateTime.now().add(budget);
    while (DateTime.now().isBefore(deadline)) {
      try {
        _refs.lookup(ref);
        return Receipt(
          tool: 'wait',
          delivery: Delivery.notDelivered,
          expectedStateReached: true,
          elapsed: DateTime.now().difference(started),
          details: {'ref': ref},
        );
      } on ControlException {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        await snapshot(includeContent: false);
      }
    }
    throw ControlException(
      ControlErrorCode.timeout,
      '等待元素 [$ref] 出现超时（${budget.inSeconds}s）',
      hint: '元素可能还没加载，或页面结构已变；重新取快照确认',
    );
  }

  /// Walks the session history by [delta] entries.
  ///
  /// Going back is not the same as navigating to the previous address: the page
  /// may be a `POST` result, a SPA route or a scroll position, and only the
  /// history entry restores it. One step back is [delta] = -1.
  ///
  /// A receipt whose [Receipt.expectedStateReached] is false means there was
  /// nowhere to go, rather than pretending a move happened.
  Future<Receipt> history({required int delta}) async {
    final started = DateTime.now();
    _ensureUsable();
    final tool = delta.isNegative ? 'back' : 'forward';
    final steps = delta.abs().clamp(1, 20);
    final urlBefore = await currentUrl();
    final linesBefore = _lastLines;

    final entries = await _historyEntries();
    final current = entries.current;
    final target = current + (delta.isNegative ? -steps : steps);
    if (entries.items.isEmpty || target < 0 || target >= entries.items.length) {
      return Receipt(
        tool: tool,
        delivery: Delivery.notDelivered,
        expectedStateReached: false,
        urlBefore: urlBefore,
        urlAfter: urlBefore,
        elapsed: DateTime.now().difference(started),
        note: delta.isNegative ? '已经没有可回退的页面了' : '已经没有可前进的页面了',
        details: {'depth': entries.items.length, 'current': current},
      );
    }

    final entry = entries.items[target];
    if (entry.id == null) {
      throw const ControlException(
        ControlErrorCode.navigation,
        '历史记录项缺少 id，无法回退',
        hint: '改用 navigate 直接打开目标地址',
      );
    }
    await _connection.send(
      'Page.navigateToHistoryEntry',
      params: {'entryId': entry.id},
    );
    final observed = await _settleAndObserve(
      urlBefore,
      linesBefore,
      waitForNavigation: true,
    );
    _refs.beginDocument();
    return Receipt(
      tool: tool,
      delivery: Delivery.notDelivered,
      pageReacted: true,
      expectedStateReached: observed.url == entry.url || observed.url != urlBefore,
      urlBefore: urlBefore,
      urlAfter: observed.url,
      elapsed: DateTime.now().difference(started),
      details: {
        'steps': steps,
        'to': entry.url,
        'depth': entries.items.length,
        'current': target,
      },
    );
  }

  Future<({List<({int? id, String url})> items, int current})> _historyEntries() async {
    try {
      final result = await _connection.send('Page.getNavigationHistory');
      final raw = (result['entries'] as List?)?.whereType<Map>() ?? const [];
      return (
        items: [
          for (final entry in raw)
            (
              id: (entry['id'] as num?)?.toInt(),
              url: entry['url']?.toString() ?? '',
            ),
        ],
        current: (result['currentIndex'] as num?)?.toInt() ?? 0,
      );
    } on ControlException {
      return (items: const <({int? id, String url})>[], current: 0);
    }
  }

  /// Hands files to a file input.
  ///
  /// The picker a person would see cannot be driven by input events, so the node
  /// is told which files to take — the route every automation tool uses. The
  /// paths must exist on the device: the model cannot invent them, so it has to
  /// ask for them.
  Future<Receipt> upload(String ref, List<String> files) async {
    final started = DateTime.now();
    _ensureUsable();
    if (files.isEmpty) {
      throw const ControlException(
        ControlErrorCode.badArguments,
        'upload 至少需要一个文件路径',
      );
    }
    final record = _refs.lookup(ref);
    final shape = await _callOnRef(record, _describeFileInputJs);
    if (shape['isFile'] != true) {
      throw ControlException(
        ControlErrorCode.notEditable,
        '元素 [${record.ref}] 不是文件选择控件（${shape['tag'] ?? record.role}）',
        hint: '用 find 找 type=file 的 input；页面上通常是一个「选择文件」按钮',
        details: {'ref': record.ref, 'role': record.role, 'tag': shape['tag']},
      );
    }
    final urlBefore = await currentUrl();
    final linesBefore = _lastLines;
    try {
      await _connection.send(
        'DOM.setFileInputFiles',
        params: {'files': files, 'backendNodeId': record.backendNodeId},
        sessionId: record.sessionId,
      );
    } on ControlException catch (error) {
      throw ControlException(
        ControlErrorCode.badArguments,
        '无法把这些文件交给页面：${error.message}',
        hint: '文件必须在这个设备上真实存在，且应用有权限读取',
        details: {'ref': record.ref, 'files': files},
      );
    }
    final applied = await _callOnRef(record, _describeFileInputJs);
    final observed = await _settleAndObserve(urlBefore, linesBefore);
    return Receipt(
      tool: 'upload',
      delivery: Delivery.unknown,
      pageReacted: observed.changed,
      expectedStateReached: applied['count'] == files.length,
      changes: observed.changes,
      urlBefore: urlBefore,
      urlAfter: observed.url,
      elapsed: DateTime.now().difference(started),
      note: '文件由脚本交给控件（系统文件选择框无法用输入事件驱动）',
      details: {
        'ref': ref,
        'role': record.role,
        'files': files,
        'count': applied['count'],
      },
    );
  }

  /// Describes a file input without touching it: what it is, and how many files
  /// it currently holds. Called before and after the handover so the receipt can
  /// say whether the page actually took them.
  static const String _describeFileInputJs = '''function() {
    const el = this;
    const isFile = el instanceof HTMLInputElement && el.type === 'file';
    return {
      isFile: isFile,
      tag: el.tagName || '',
      count: isFile ? el.files.length : 0,
      accept: isFile ? (el.getAttribute('accept') || '') : '',
    };
  }''';

  /// Answers an open `window.confirm`/`prompt`.
  ///
  /// A dialog freezes the page, so this is the only call that works until it is
  /// answered. A payment, password or one-time-code step is never answered by
  /// the layer; the caller hands it to the person.
  Future<Receipt> handleDialog({required bool accept, String? promptText}) async {
    // Not _ensureUsable: an open dialog is exactly the state this call exists to
    // leave, so refusing it here would make the dialog impossible to dismiss.
    _ensureConnected();
    await _connection.send('Page.handleJavaScriptDialog', params: {
      'accept': accept,
      if (promptText != null) 'promptText': promptText,
    });
    _dialogOpen = false;
    return Receipt(
      tool: 'handleDialog',
      delivery: Delivery.delivered,
      details: {'accept': accept},
    );
  }

  bool get hasOpenDialog => _dialogOpen;

  /// Finds controls by name or role in a fresh outline.
  ///
  /// An agent that has to pick one of eighty similar rows will guess; this is
  /// what it should use instead. Only what the outline showed can match, so a
  /// returned ref is always usable.
  Future<({List<OutlineLine> matches, int total})> find(
    String? query, {
    String? role,
    bool exact = false,
    int limit = 20,
  }) async {
    final outline = await snapshot(includeContent: false);
    final matches = matchEntries(
      outline.entries,
      query: query,
      role: role,
      exact: exact,
      limit: limit,
    );
    return (matches: matches, total: outline.entries.length);
  }

  /// A PNG of the page, for a vision model or a step card.
  Future<({String base64, int bytes, int nodeCount})> screenshot({
    bool fullPage = false,
  }) async {
    _ensureUsable();
    final result = await _connection.send('Page.captureScreenshot', params: {
      'format': 'png',
      if (fullPage) 'captureBeyondViewport': true,
    });
    final data = result['data'] as String? ?? '';
    if (data.isEmpty) {
      throw const ControlException(
        ControlErrorCode.captureFailed,
        '截图失败：没有拿到图像数据',
      );
    }
    return (base64: data, bytes: data.length, nodeCount: _lastLines.length);
  }

  Future<void> detach() async {
    await _events?.cancel();
    await _connection.close();
  }

  /// Fails a tool call the way the page's state requires.
  void _ensureConnected() {
    if (_connection.isClosed) {
      throw const ControlException(
        ControlErrorCode.targetMissing,
        '页面连接已断开',
        hint: '重新附加后再试',
      );
    }
  }

  void _ensureUsable() {
    if (_connection.isClosed) {
      throw const ControlException(
        ControlErrorCode.targetMissing,
        '页面连接已断开',
        hint: '重新附加后再试',
      );
    }
    if (_dialogOpen) {
      throw const ControlException(
        ControlErrorCode.dialogOpen,
        '页面上有未处理的弹窗，页面已冻结',
        hint: '先处理弹窗（接受或取消），再继续操作',
      );
    }
  }

  void _note(String note) {
    if (!_notes.contains(note)) _notes.add(note);
  }

  static const List<String> _keyNames = [
    'Enter',
    'Tab',
    'Escape',
    'Backspace',
    'Delete',
    'ArrowUp',
    'ArrowDown',
    'ArrowLeft',
    'ArrowRight',
    'Space',
  ];
}
