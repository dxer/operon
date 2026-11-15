import 'interaction/input.dart';
import 'protocol/errors.dart';
import 'protocol/gesture.dart';
import 'protocol/results.dart';
import 'transport/devtools_socket.dart';
import 'tab_host.dart';
import 'transport/endpoint.dart' show CdpTarget, SocketConnector;
import 'session.dart';

part 'control_catalog.dart';

/// The control layer as one callable object.
///
/// A caller picks a tool by name and passes plain arguments, which keeps the
/// same call shape for the agent, a recorded flow, and a diagnostic.
class Control {
  Control._(
    this._session, {
    required SocketConnector connect,
    TabHost? tabHost,
  })  : _connect = connect,
        _tabHost = tabHost;

  /// The app's tab strip, when the caller has one. Absent in tests and in any
  /// embedding that only speaks CDP: the layer then still works, it just
  /// cannot make the user's screen follow it.
  final TabHost? _tabHost;

  static Future<Control> attach({
    String? urlHint,
    String? targetId,
    DevToolsAddress? address,
    SocketConnector? connect,
    TabHost? tabHost,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final session = await ControlSession.attach(
      address: address,
      connect: connect,
      urlHint: urlHint,
      targetId: targetId,
      timeout: timeout,
    );
    return Control._(
      session,
      tabHost: tabHost,
      connect: connect ??
          () async {
            final address = await findDevToolsAddress();
            return connectDevTools(address, timeout: timeout);
          },
    );
  }

  /// The connector kept for a tab switch. Switching pages means a new
  /// connection, and re-discovering the socket every time would be work done
  /// twice for no reason.
  final SocketConnector _connect;

  ControlSession _session;

  ControlSession get session => _session;

  /// Notified before an input is dispatched, with the point and box it lands on.
  ///
  /// The layer decides both, so the overlay can never animate a place the click
  /// did not go.
  void Function(GestureTarget target)? get onGesture => session.onGesture;

  set onGesture(void Function(GestureTarget target)? value) =>
      session.onGesture = value;

  String get url => session.target.url;

  List<String> get notes => session.notes;

  Future<void> detach() => _session.detach();

  /// The pages the app has open, with the attached one marked.
  Future<ToolResult> _listTabs() async {
    final pages = await ControlSession.listTabs(connect: _connect);
    if (pages.isEmpty) {
      return const ToolResult(
        ok: true,
        text: '当前没有打开的标签页',
        data: {'tabs': <Object?>[], 'count': 0},
      );
    }
    final attachedId = _session.target.id;
    final lines = <String>[];
    final data = <Object?>[];
    for (var index = 0; index < pages.length; index++) {
      final page = pages[index];
      final here = page.id == attachedId;
      final title = page.title.trim().isEmpty ? '(无标题)' : page.title.trim();
      lines.add('[$index] ${here ? '←当前 ' : ''}$title — ${page.url} (id ${page.id})');
      data.add({
        'index': index,
        'id': page.id,
        'url': page.url,
        'title': page.title,
        'attached': here,
      });
    }
    return ToolResult(
      ok: true,
      text: lines.join('\n'),
      data: {'tabs': data, 'count': pages.length},
    );
  }

  Future<void> _attachToTarget(String targetId) async {
    final previous = _session;
    final gesture = previous.onGesture;
    final next = await ControlSession.attach(
      connect: _connect,
      targetId: targetId,
    );
    next.onGesture = gesture;
    await previous.detach();
    _session = next;
  }

  /// Moves the layer onto another page.
  ///
  /// A new connection, not a switch inside one: each page has its own DevTools
  /// target, and every ref belongs to the document it came from. The old session
  /// is detached first so two pages are never driven at once.
  Future<ToolResult> _switchTab(String wanted) async {
    final pages = await ControlSession.listTabs(connect: _connect);
    if (pages.isEmpty) {
      return const ToolResult(ok: false, text: '当前没有打开的标签页');
    }
    final index = int.tryParse(wanted);
    final target = pages.where((page) => page.id == wanted).firstOrNull ??
        (index != null && index >= 0 && index < pages.length ? pages[index] : null);
    if (target == null) {
      return ToolResult(
        ok: false,
        text: '找不到标签页「$wanted」',
        data: {'ids': [for (final page in pages) page.id]},
      );
    }
    if (target.id == _session.target.id) {
      return ToolResult(ok: true, text: '已经在这个标签页上：${target.url}');
    }
    await _attachToTarget(target.id);
    // The app has its own idea of which tab is in front, and until this call
    // it did not follow: the agent worked on a page the user could not see.
    final shown = await _tabHost?.activate?.call(target) ?? false;
    return ToolResult(
      ok: true,
      text: '已切换到 ${target.title.trim().isEmpty ? target.url : target.title}'
          '（${target.url}），ref 需要重新 snapshot'
          '${_tabHost != null && !shown ? '。注意：界面上没能切到该标签页，用户看到的可能不是这一页' : ''}',
      data: {'id': target.id, 'url': target.url, 'title': target.title},
    );
  }

  /// Closes a tab through the app, because only the app can.
  ///
  /// The session moves off the page *before* the page goes away: a tool that
  /// closed its own target first would leave the layer attached to nothing and
  /// every later call failing at once.
  Future<ToolResult> _closeTab(String? wanted) async {
    final host = _tabHost;
    if (host?.close == null) {
      return const ToolResult(
        ok: false,
        text: '这个环境不能关闭标签页',
        data: {'reason': 'no-tab-host'},
      );
    }
    final pages = await ControlSession.listTabs(connect: _connect);
    if (pages.isEmpty) {
      return const ToolResult(ok: false, text: '当前没有打开的标签页');
    }
    final index = wanted == null ? null : int.tryParse(wanted);
    final target = wanted == null
        ? pages.firstWhere((page) => page.id == _session.target.id,
            orElse: () => pages.first)
        : pages.where((page) => page.id == wanted).firstOrNull ??
            (index != null && index >= 0 && index < pages.length
                ? pages[index]
                : null);
    if (target == null) {
      return ToolResult(
        ok: false,
        text: '找不到标签页「$wanted」',
        data: {'ids': [for (final page in pages) page.id]},
      );
    }
    if (pages.length <= 1) {
      return const ToolResult(
        ok: false,
        text: '这是最后一个标签页，不能关闭',
        data: {'reason': 'last-tab'},
      );
    }

    final closingCurrent = target.id == _session.target.id;
    CdpTarget? fallback;
    for (final page in pages) {
      if (page.id != target.id) {
        fallback = page;
        break;
      }
    }
    if (closingCurrent && fallback != null) {
      await _attachToTarget(fallback.id);
      await host!.activate?.call(fallback);
    }

    final closed = await host!.close!(target);
    if (!closed) {
      return const ToolResult(
        ok: false,
        text: '应用拒绝了关闭这个标签页',
        data: {'reason': 'refused'},
      );
    }
    return ToolResult(
      ok: true,
      text: '已关闭 ${target.title.trim().isEmpty ? target.url : target.title}'
          '（${target.url}）${closingCurrent ? '，现在在 ${_session.target.url}' : ''}',
      data: {'id': target.id, 'url': target.url},
    );
  }

  /// Opens a URL in a new tab and moves the layer there.
  ///
  /// The wait is for the target, not for the page: a slow site would otherwise
  /// turn "open this" into a timeout, and the model is going to snapshot next
  /// anyway.
  Future<ToolResult> _navigateNewTab(String url) async {
    final host = _tabHost;
    if (host?.open == null) {
      return const ToolResult(
        ok: false,
        text: '这个环境不能新开标签页',
        data: {'reason': 'no-tab-host'},
      );
    }
    final before = {
      for (final page in await ControlSession.listTabs(connect: _connect))
        page.id,
    };
    await host!.open!(url);

    CdpTarget? opened;
    for (var attempt = 0; attempt < 25; attempt++) {
      final pages = await ControlSession.listTabs(connect: _connect);
      opened = pages
          .where((page) => !before.contains(page.id) && page.isPage)
          .firstOrNull;
      if (opened != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (opened == null) {
      return ToolResult(
        ok: false,
        text: '新标签页没有出现',
        data: {'url': url},
      );
    }
    await _attachToTarget(opened.id);
    return ToolResult(
      ok: true,
      text: '已在新标签页打开 $url，当前页仍是原来的那个；这一页需要重新 snapshot',
      data: {'id': opened.id, 'url': opened.url},
    );
  }

  /// Runs one tool. Failures come back as a [ToolResult], not as an exception,
  /// so a caller never has to tell a protocol error from a bug.
  Future<ToolResult> execute(String tool, [Map<String, Object?> args = const {}]) async {
    try {
      switch (tool) {
        case 'snapshot':
          final outline = await session.snapshot(includeContent: _bool(args, 'content') ?? true);
          return ToolResult(
            ok: true,
            text: outline.render(),
            data: {
              'url': outline.url,
              'title': outline.title,
              'elements': outline.entries.length,
              'truncated': outline.truncated,
              if (outline.omitted.isNotEmpty) 'omitted': outline.omitted,
            },
          );
        case 'read':
          final outline = await session.snapshot(includeContent: true);
          final limit = _int(args, 'limit') ?? 14;
          final content = outline.content.take(limit).toList();
          return ToolResult(
            ok: true,
            text: content.isEmpty ? '(页面上没有可读的文字)' : content.join('\n\n'),
            data: {
              'url': outline.url,
              'title': outline.title,
              'blocks': content.length,
            },
          );
        case 'find':
          final found = await session.find(
            _string(args, 'query'),
            role: _string(args, 'role'),
            exact: _bool(args, 'exact') ?? false,
            limit: _int(args, 'limit') ?? 20,
          );
          return ToolResult(
            ok: true,
            text: found.matches.isEmpty
                ? '没有匹配的控件（页面共 ${found.total} 个可操作元素）'
                : found.matches.map((entry) => entry.render().trimLeft()).join('\n'),
            data: {
              'matches': found.matches.length,
              'total': found.total,
              'refs': found.matches.map((entry) => entry.ref).toList(),
            },
          );
        case 'screenshot':
          final shot = await session.screenshot(fullPage: _bool(args, 'fullPage') ?? false);
          return ToolResult(
            ok: true,
            text: '已截取页面（PNG，约 ${(shot.bytes / 1024).round()} KB）',
            data: {
              'image': shot.base64,
              'mimeType': 'image/png',
              'bytes': shot.bytes,
            },
          );
        case 'click':
          final receipt = await session.click(
            _requireRef(args),
            mode: _modeOf(_string(args, 'mode')),
          );
          return ToolResult(ok: true, text: receipt.summary, receipt: receipt);
        case 'clear':
          // One implementation, two intentions: `clear` is `type` with empty
          // text and replace, and exists so the model does not have to guess
          // that combination.
          final receipt = await session.type(_requireRef(args), '', replace: true);
          return ToolResult(
            ok: true,
            text: '已清空这个输入框',
            receipt: receipt,
          );
        case 'type':
          final receipt = await session.type(
            _requireRef(args),
            _string(args, 'text') ?? '',
            replace: _bool(args, 'replace') ?? false,
            submit: _bool(args, 'submit') ?? false,
            secret: _bool(args, 'secret') ?? false,
          );
          return ToolResult(ok: true, text: receipt.summary, receipt: receipt);
        case 'select':
          final receipt = await session.select(
            _requireRef(args),
            label: _string(args, 'optionLabel'),
            value: _string(args, 'optionValue'),
            index: _int(args, 'optionIndex'),
          );
          return ToolResult(ok: true, text: receipt.summary, receipt: receipt);
        case 'hover':
          final receipt = await session.hover(_requireRef(args));
          return ToolResult(ok: true, text: receipt.summary, receipt: receipt);
        case 'press':
          final key = _string(args, 'key');
          if (key == null || key.isEmpty) {
            throw const ControlException(ControlErrorCode.badArguments, 'press 需要一个 key 参数');
          }
          final receipt = await session.press(key);
          return ToolResult(ok: true, text: receipt.summary, receipt: receipt);
        case 'scroll':
          final receipt = await session.scroll(
            direction: _string(args, 'direction') ?? 'down',
            amount: _int(args, 'amount'),
            ref: _string(args, 'ref'),
          );
          return ToolResult(ok: true, text: receipt.summary, receipt: receipt);
        case 'navigate':
          final url = _string(args, 'url');
          if (url == null || url.isEmpty) {
            throw const ControlException(ControlErrorCode.badArguments, 'navigate 需要一个 url 参数');
          }
          if (_bool(args, 'newTab') == true) {
            return _navigateNewTab(url);
          }
          final receipt = await session.navigate(url);
          return ToolResult(ok: true, text: receipt.summary, receipt: receipt);
        case 'back':
          final receipt = await session.history(delta: -(_int(args, 'steps') ?? 1));
          return ToolResult(ok: true, text: receipt.summary, receipt: receipt);
        case 'forward':
          final receipt = await session.history(delta: _int(args, 'steps') ?? 1);
          return ToolResult(ok: true, text: receipt.summary, receipt: receipt);
        case 'tabs':
          return _listTabs();
        case 'switch_tab':
          final wanted = _string(args, 'tabId');
          if (wanted == null || wanted.isEmpty) {
            throw const ControlException(ControlErrorCode.badArguments, 'switch_tab 需要一个 tabId 参数');
          }
          return _switchTab(wanted);
        case 'close_tab':
          return _closeTab(_string(args, 'tabId'));
        case 'upload':
          final files = (_string(args, 'files') ?? '')
              .split(',')
              .map((path) => path.trim())
              .where((path) => path.isNotEmpty)
              .toList(growable: false);
          final receipt = await session.upload(_requireRef(args), files);
          return ToolResult(ok: true, text: receipt.summary, receipt: receipt);
        case 'wait':
          final receipt = await session.wait(
            ref: _string(args, 'ref'),
            ms: _int(args, 'ms'),
          );
          return ToolResult(ok: true, text: receipt.summary, receipt: receipt);
        case 'handle_dialog':
          final receipt = await session.handleDialog(
            accept: _bool(args, 'accept') ?? false,
            promptText: _string(args, 'promptText'),
          );
          return ToolResult(ok: true, text: receipt.summary, receipt: receipt);
        default:
          throw ControlException(
            ControlErrorCode.unsupported,
            '未知工具：$tool',
            hint: '可用工具：${controlToolCatalog.map((spec) => spec.name).join('、')}',
          );
      }
    } on ControlException catch (error) {
      return ToolResult.failure(error);
    }
  }

  static String _requireRef(Map<String, Object?> args) {
    final ref = _string(args, 'ref');
    if (ref == null || ref.isEmpty) {
      // The model forgot an argument; that is a bad call, not a bug in here.
      throw const ControlException(
        ControlErrorCode.badArguments,
        '这个工具需要一个 ref 参数',
        hint: 'ref 来自最近一次 snapshot，例如 a3',
      );
    }
    return ref;
  }

  static InputMode? _modeOf(String? mode) {
    switch (mode) {
      case 'mouse':
        return InputMode.mouse;
      case 'touch':
        return InputMode.touch;
      case 'auto':
        return InputMode.auto;
      default:
        return null;
    }
  }

  // Tool arguments arrive as whatever the model wrote. A model that sends
  // "true" for a boolean or "20" for a number is common enough that coercing
  // here is cheaper than failing a whole step over it.
  static String? _string(Map<String, Object?> args, String key) {
    final value = args[key];
    if (value == null) return null;
    if (value is String) return value;
    return '$value';
  }

  static bool? _bool(Map<String, Object?> args, String key) {
    final value = args[key];
    if (value == null) return null;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = '$value'.toLowerCase();
    if (text == 'true' || text == '1' || text == 'yes') return true;
    if (text == 'false' || text == '0' || text == 'no') return false;
    return null;
  }

  static int? _int(Map<String, Object?> args, String key) {
    final value = args[key];
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse('$value');
  }
}
