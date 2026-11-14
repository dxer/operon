import 'interaction/input.dart';
import 'session.dart';
import 'transport/endpoint.dart';
import 'transport/devtools_socket.dart';

/// One result line in the control layer's self-check.
class DiagnosticCheck {
  const DiagnosticCheck({
    required this.name,
    required this.ok,
    this.detail = '',
    this.ms,
    this.data,
  });

  final String name;

  /// False means "this capability is missing"; the detail says what happened.
  final bool ok;
  final String detail;
  final int? ms;
  final Map<String, Object?>? data;
}

/// The spike behind the control layer, runnable from the app.
///
/// These checks answer the only question that matters before the agent is
/// written: can this WebView be read and driven the way the design needs? Each
/// one is independent, so a failure names the capability that is missing rather
/// than "the layer does not work".
class ControlDiagnostics {
  /// Runs the checks against the WebView's own DevTools socket.
  const ControlDiagnostics();

  /// Read-only checks. Safe to run on any page.
  Future<List<DiagnosticCheck>> runSafe({String? urlHint}) async {
    final checks = <DiagnosticCheck>[];
    DevToolsAddress? address;

    checks.add(await _timed('调试通道', () async {
      address = await findDevToolsAddress();
      final found = address!;
      return DiagnosticCheck(
        name: '调试通道',
        ok: true,
        detail: '${found.name}（pid ${found.pid}）',
        data: {'socket': found.name, 'pid': found.pid},
      );
    }));

    if (address == null) return checks;
    final devtools = address!;

    checks.add(await _timed('页面发现', () async {
      final targets = await listTargets(
        connect: () => connectDevTools(devtools),
      );
      final pages = targets.where((target) => target.isPage).toList();
      return DiagnosticCheck(
        name: '页面发现',
        ok: pages.isNotEmpty,
        detail: '${targets.length} 个 target，其中 ${pages.length} 个页面'
            '${pages.isEmpty ? '' : '：${pages.first.url}'}',
        data: {'targets': targets.map((t) => t.url).toList()},
      );
    }));

    ControlSession? session;
    try {
      session = await ControlSession.attach(address: devtools, urlHint: urlHint);
    } catch (error) {
      checks.add(DiagnosticCheck(
        name: '附加页面',
        ok: false,
        detail: '$error',
      ));
      return checks;
    }

    final active = session;
    try {
      checks.add(await _timed('运行时通道', () async {
        final value = await _evaluate(active, 'document.readyState');
        return DiagnosticCheck(
          name: '运行时通道',
          ok: value != null,
          detail: value == null ? 'Runtime.evaluate 没有返回值' : 'document.readyState = $value',
        );
      }));

      checks.add(await _timed('无障碍树', () async {
        final outline = await active.snapshot();
        return DiagnosticCheck(
          name: '无障碍树',
          ok: outline.entries.isNotEmpty,
          detail: '可操作元素 ${outline.entries.length} 个，'
              '文字 ${outline.content.length} 段'
              '${outline.truncated ? '（已截断）' : ''}',
          data: {
            'entries': outline.entries.length,
            'omitted': outline.omitted,
          },
        );
      }));

      checks.add(await _timed('几何与命中', () async {
        final outline = await active.snapshot(includeContent: false);
        final first = outline.entries.isEmpty ? null : outline.entries.first;
        if (first == null) {
          return const DiagnosticCheck(
            name: '几何与命中',
            ok: false,
            detail: '页面上没有可操作元素，无法验证',
          );
        }
        final quads = await active.connection.send(
          'DOM.getContentQuads',
          params: {'backendNodeId': first.backendNodeId},
          sessionId: first.frameId,
        );
        final raw = quads['quads'];
        final count = raw is List ? raw.length : 0;
        return DiagnosticCheck(
          name: '几何与命中',
          ok: count > 0,
          detail: count > 0
              ? '${first.role} 命中 $count 个四边形，坐标可用'
              : '${first.role} 没有可点击区域（可能不可见）',
          data: {'ref': first.ref, 'role': first.role},
        );
      }));

      checks.add(await _timed('输入域', () async {
        // A pointer move, not a click: it proves the domain answers without
        // touching anything on the page.
        await active.connection.send('Input.dispatchMouseEvent', params: {
          'type': 'mouseMoved',
          'x': 2,
          'y': 2,
          'button': 'none',
        });
        return const DiagnosticCheck(
          name: '输入域',
          ok: true,
          detail: 'Input 域可用（已派发一次无副作用的指针移动）',
        );
      }));

      checks.add(await _timed('截图', () async {
        final shot = await active.connection.send('Page.captureScreenshot', params: {
          'format': 'png',
        });
        final data = shot['data'] as String? ?? '';
        return DiagnosticCheck(
          name: '截图',
          ok: data.isNotEmpty,
          detail: data.isEmpty ? '没有拿到截图' : 'PNG base64 ${(data.length / 1024).round()} KB',
          data: {'bytes': data.length},
        );
      }));

      checks.add(DiagnosticCheck(
        name: '子 frame',
        ok: true,
        detail: active.childSessionCount == 0
            ? '当前页面没有独立 iframe 会话'
            : '已附加 ${active.childSessionCount} 个子 frame',
      ));

      if (active.notes.isNotEmpty) {
        checks.add(DiagnosticCheck(
          name: '注意',
          ok: true,
          detail: active.notes.join('；'),
        ));
      }
    } finally {
      await active.detach();
    }
    return checks;
  }

  /// Compares a real CDP input event with a script-synthesised one.
  ///
  /// This is the whole point of the rewrite in one number: the page must report
  /// `isTrusted: true` for what the layer sends, and `false` for what the old
  /// layer sent. Tapping is not read-only, so this check is separate and the UI
  /// says so before running it.
  Future<DiagnosticCheck> probeInputTrust({String? urlHint}) async {
    ControlSession? session;
    try {
      final devtools = await findDevToolsAddress();
      session = await ControlSession.attach(address: devtools, urlHint: urlHint);
      final active = session;
      await _evaluate(active, '''
        window.__operonProbe = {};
        document.addEventListener('pointerdown', function (event) {
          window.__operonProbe.pointer = {
            isTrusted: event.isTrusted,
            type: event.type,
            tag: event.target && event.target.tagName
          };
        }, {capture: true, once: true});
        document.addEventListener('click', function (event) {
          window.__operonProbe.click = event.isTrusted;
        }, {capture: true, once: true});
        'installed';
      ''');

      final metrics = await active.connection.send('Page.getLayoutMetrics');
      final viewport = metrics['cssLayoutViewport'] ?? metrics['layoutViewport'];
      final width = (viewport is Map ? (viewport['clientWidth'] as num?)?.toDouble() : null) ?? 400;
      final height = (viewport is Map ? (viewport['clientHeight'] as num?)?.toDouble() : null) ?? 800;
      await tapAt(
        active.connection,
        x: width / 2,
        y: height / 2,
        mode: InputMode.touch,
      );
      await Future<void>.delayed(const Duration(milliseconds: 250));

      final raw = await _evaluate(active, 'JSON.stringify(window.__operonProbe || {})');
      final synthetic = await _evaluate(active, '''
        (function () {
          let trusted = null;
          const listener = function (event) {
            trusted = event.isTrusted;
            document.removeEventListener('click', listener, true);
          };
          document.addEventListener('click', listener, true);
          document.body.dispatchEvent(new MouseEvent('click', {bubbles: true}));
          return String(trusted);
        })();
      ''');

      final pointer = raw != null && raw.contains('"pointer"');
      final trusted = raw != null && raw.contains('"isTrusted":true');
      final ok = pointer && trusted && synthetic == 'false';
      return DiagnosticCheck(
        name: '真实输入',
        ok: ok,
        detail: ok
            ? 'CDP 派发的事件 isTrusted=true；页面脚本合成的是 false'
            : 'CDP 事件没有被页面当成真实输入（probe=$raw，合成事件=$synthetic）',
        data: {'cdp': raw, 'syntheticIsTrusted': synthetic},
      );
    } catch (error) {
      return DiagnosticCheck(name: '真实输入', ok: false, detail: '$error');
    } finally {
      await session?.detach();
    }
  }

  Future<String?> _evaluate(ControlSession session, String expression) async {
    final result = await session.connection.send(
      'Runtime.evaluate',
      params: {
        'expression': expression,
        'returnByValue': true,
        'awaitPromise': false,
      },
    );
    final value = result['result'];
    if (value is Map) {
      final raw = value['value'];
      if (raw != null) return '$raw';
      final description = value['description'];
      if (description != null) return '$description';
    }
    return null;
  }

  Future<DiagnosticCheck> _timed(
    String name,
    Future<DiagnosticCheck> Function() body,
  ) async {
    final started = DateTime.now();
    try {
      final check = await body();
      return DiagnosticCheck(
        name: check.name,
        ok: check.ok,
        detail: check.detail,
        ms: DateTime.now().difference(started).inMilliseconds,
        data: check.data,
      );
    } catch (error) {
      return DiagnosticCheck(
        name: name,
        ok: false,
        detail: '$error',
        ms: DateTime.now().difference(started).inMilliseconds,
      );
    }
  }
}
