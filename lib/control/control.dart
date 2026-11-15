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
        case 'fill_form':
          // `await` matters: without it the failure would escape the catch
          // below, and a bad ref would reach the caller as an exception.
          return await _fillForm(args);
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

  /// Fills several fields as one call.
  ///
  /// Every ref is resolved before the first keystroke: a half-filled form the
  /// model did not intend is worse than a failed call, because the page may
  /// already have reacted to the first field. A failure after typing starts is
  /// reported with what was filled, not folded into a bare error.
  Future<ToolResult> _fillForm(Map<String, Object?> args) async {
    final rawFields = args['fields'];
    if (rawFields is! List || rawFields.isEmpty) {
      throw const ControlException(
        ControlErrorCode.badArguments,
        'fill_form 需要至少一个字段',
        hint: 'fields 是数组，每项至少包含 ref 和 value；'
            '例如 [{"ref":"a3","value":"张三"}]',
      );
    }

    final rawSubmitRef = _string(args, 'submitRef')?.trim() ?? '';
    // Existence is checked now; the disabled state is not. A submit button is
    // often disabled precisely until the form has been filled, so judging it
    // before the fields would reject the normal case. The click after filling
    // reads the state the page actually reached.
    final submitRecord =
        rawSubmitRef.isEmpty ? null : session.refs.lookup(rawSubmitRef);

    final fields = <_FillField>[];
    for (var index = 0; index < rawFields.length; index++) {
      final field = _parseFillField(rawFields[index], index);
      if (submitRecord != null && field.ref == submitRecord.ref) {
        throw ControlException(
          ControlErrorCode.badArguments,
          'submitRef 不能同时是一个填写字段（[${field.ref}]）',
          hint: '提交按钮只放在 submitRef 里，不要放进 fields',
          details: {'ref': field.ref},
        );
      }
      fields.add(field);
    }

    final started = DateTime.now();
    final urlBefore = await session.currentUrl();
    final filled = <Map<String, Object?>>[];
    final changes = <String>[];
    final selectOutcomes = <bool>[];
    var anyDelivered = false;
    var anySelect = false;
    var pageReacted = false;
    var urlAfter = urlBefore;

    for (var index = 0; index < fields.length; index++) {
      final field = fields[index];
      final Receipt receipt;
      try {
        receipt = field.action == 'select'
            ? await session.select(
                field.ref,
                label: field.value.isEmpty ? null : field.value,
                value: field.optionValue ??
                    (field.value.isEmpty ? null : field.value),
                index: field.optionIndex,
                observe: false,
              )
            : await session.type(
                field.ref,
                field.value,
                replace: field.replace,
                secret: field.secret,
                observe: false,
              );
      } on ControlException catch (error) {
        return _fillFailure(
          error,
          fields: fields,
          filled: filled,
          failedIndex: index,
          delivery: anyDelivered ? Delivery.delivered : Delivery.unknown,
          pageReacted: pageReacted,
          changes: changes,
          urlBefore: urlBefore,
          urlAfter: urlAfter,
          started: started,
        );
      }

      if (field.action == 'select') {
        anySelect = true;
        if (receipt.expectedStateReached != null) {
          selectOutcomes.add(receipt.expectedStateReached!);
        }
      } else {
        anyDelivered = true;
      }
      if (receipt.pageReacted == true) pageReacted = true;
      if (receipt.urlAfter != null) urlAfter = receipt.urlAfter!;
      changes.addAll(receipt.changes);
      filled.add({
        'ref': field.ref,
        'label': field.label,
        'action': field.action,
        if (field.secret)
          'secret': true
        else if (field.value.isNotEmpty)
          'value': _clip(field.value, 200),
        'delivery': receipt.delivery.name,
      });
    }

    // One capture for the whole batch: fields are independent by contract, so
    // there is nothing to learn between them. The submit click below observes
    // again on top of this state, so its diff contains only the submit itself.
    try {
      final observed = await session.observe();
      if (observed.changed) pageReacted = true;
      urlAfter = observed.url;
      changes.addAll(observed.changes);
    } on ControlException catch (error) {
      // The fields are already in the page. A bare "read failed" would invite
      // the model to type them all again.
      return ToolResult(
        ok: false,
        error: ControlException(
          error.code,
          '已填写 ${filled.length} 个字段，但读取填写后的页面状态失败：'
              '${error.message}',
          hint: error.hint ??
              '字段已经写入页面；先 snapshot 确认现状，不要重新填写全部字段',
          details: {
            ...?error.details,
            'filled': filled.length,
          },
        ),
        data: {
          'fields': filled,
          'fieldCount': filled.length,
          'submitted': false,
          'url': urlAfter,
        },
        receipt: Receipt(
          tool: 'fill_form',
          delivery: anyDelivered
              ? Delivery.delivered
              : anySelect
                  ? Delivery.unknown
                  : Delivery.notDelivered,
          changes: changes.take(40).toList(),
          urlBefore: urlBefore,
          urlAfter: urlAfter,
          elapsed: DateTime.now().difference(started),
          note: '字段已填入，但没能读取填写后的页面状态',
          details: {'fields': filled},
        ),
      );
    }

    Receipt? submitted;
    if (submitRecord != null) {
      try {
        submitted = await session.click(submitRecord.ref);
      } on ControlException catch (error) {
        return ToolResult(
          ok: false,
          error: ControlException(
            error.code,
            '已填写 ${filled.length} 个字段，但提交失败：${error.message}',
            hint: error.code == ControlErrorCode.disabled
                ? '字段已填入，但表单仍认为不能提交；'
                    '重新 snapshot 检查必填项、校验提示或同意勾选'
                : error.hint ??
                    '已填的字段保留在页面上；重新 snapshot 确认提交按钮，'
                        '必要时用 click 重试，不要重新填写全部字段',
            details: {
              ...?error.details,
              'filled': filled.length,
              'submitRef': submitRecord.ref,
            },
          ),
          data: {
            'fields': filled,
            'fieldCount': filled.length,
            'submitted': false,
            'url': urlAfter,
          },
          receipt: Receipt(
            tool: 'fill_form',
            delivery: anyDelivered
                ? Delivery.delivered
                : anySelect
                    ? Delivery.unknown
                    : Delivery.notDelivered,
            pageReacted: pageReacted,
            changes: changes.take(40).toList(),
            urlBefore: urlBefore,
            urlAfter: urlAfter,
            elapsed: DateTime.now().difference(started),
            note: '字段已填入，提交没有成功',
            details: {'fields': filled},
          ),
        );
      }
      pageReacted = pageReacted || submitted.pageReacted == true;
      urlAfter = submitted.urlAfter ?? urlAfter;
      changes.addAll(submitted.changes);
    }

    final reached =
        selectOutcomes.isEmpty ? null : selectOutcomes.every((value) => value);
    final submittedReceipt = submitted;
    final buffer = StringBuffer('已填写 ${filled.length} 个字段');
    if (submitRecord == null) {
      buffer.write('（未提交）');
    } else {
      buffer.write('，并点击「${_displayName(submitRecord.label)}」提交');
    }
    buffer.write('。');
    if (anySelect) buffer.write('下拉项由脚本设置选中值。');
    if (reached == false) {
      buffer.write('有下拉项没有达到预期值，重新 snapshot 确认页面反映的选择。');
    }

    return ToolResult(
      ok: true,
      text: buffer.toString(),
      data: {
        'fields': filled,
        'fieldCount': filled.length,
        'submitted': submitted != null,
        'url': urlAfter,
      },
      receipt: Receipt(
        tool: submitted == null ? 'fill_form' : 'fill_form+submit',
        delivery: submitted != null || anyDelivered
            ? Delivery.delivered
            : Delivery.unknown,
        pageReacted: pageReacted,
        expectedStateReached: reached,
        changes: changes.take(40).toList(),
        urlBefore: urlBefore,
        urlAfter: urlAfter,
        elapsed: DateTime.now().difference(started),
        note: anySelect
            ? '原生下拉项由脚本设置（系统弹层无法用鼠标事件驱动）'
            : null,
        details: {
          'fields': filled,
          if (submitRecord != null && submittedReceipt != null)
            'submit': {
              'ref': submitRecord.ref,
              'label': submitRecord.label,
              'delivery': submittedReceipt.delivery.name,
              'pageReacted': submittedReceipt.pageReacted,
            },
        },
      ),
    );
  }

  _FillField _parseFillField(Object? raw, int index) {
    if (raw is! Map) {
      throw ControlException(
        ControlErrorCode.badArguments,
        'fields[$index] 必须是一个对象',
        hint: '每项形如 {"ref":"a3","value":"张三"}',
      );
    }
    // JSON keys are strings; anything else is a malformed call, not a reason
    // to crash the layer with a cast error.
    final field = <String, Object?>{
      for (final entry in raw.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
    final ref = _string(field, 'ref')?.trim() ?? '';
    if (ref.isEmpty) {
      throw ControlException(
        ControlErrorCode.badArguments,
        'fields[$index] 缺少 ref',
        hint: 'ref 来自最近一次 snapshot，例如 a3',
      );
    }
    final record = session.refs.lookup(ref);
    if (record.disabled) {
      throw ControlException(
        ControlErrorCode.disabled,
        '字段 [${record.ref}]（${record.label}）当前不可用',
        hint: '等待页面加载完成，或先处理掉遮挡/禁用它的情况',
        details: {'ref': record.ref, 'role': record.role},
      );
    }
    final rawAction = _string(field, 'action')?.trim().toLowerCase() ?? '';
    // Typing into a native `<select>` silently selects nothing. A combobox or
    // listbox without an explicit action is therefore treated as a dropdown:
    // a custom dropdown then fails loudly and the model can retry with
    // action=type, which is the recoverable direction.
    final roleHintsSelect =
        record.role == 'combobox' || record.role == 'listbox';
    final action = rawAction.isEmpty
        ? (roleHintsSelect ? 'select' : 'type')
        : rawAction;
    if (action != 'type' && action != 'select') {
      throw ControlException(
        ControlErrorCode.badArguments,
        'fields[$index] 的 action 只能是 type 或 select，收到「$action」',
        details: {'ref': record.ref, 'action': action},
      );
    }
    if (action == 'type') {
      if (record.role == 'Iframe') {
        throw ControlException(
          ControlErrorCode.notEditable,
          '字段 [${record.ref}] 是 iframe，不能直接输入文字',
          hint: '读取 iframe 内部的输入框，用它的 ref 填写',
          details: {'ref': record.ref},
        );
      }
      if (!record.editable) {
        throw ControlException(
          ControlErrorCode.notEditable,
          '字段 [${record.ref}] 不接受文字输入（${record.role}）',
          hint: '输入框用 type；原生下拉把 action 设为 select；需要点击的用 click',
          details: {'ref': record.ref, 'role': record.role},
        );
      }
    }
    final value = _string(field, 'value') ?? '';
    // A missing value is a malformed call, not a request to clear: clearing a
    // field by accident is not something a form fill should ever do.
    if (action == 'type' && !field.containsKey('value')) {
      throw ControlException(
        ControlErrorCode.badArguments,
        '字段 [${record.ref}] 缺少 value',
        hint: '要清空这个输入框，请显式传 "value": ""；否则填入要写的文字',
        details: {'ref': record.ref},
      );
    }
    final optionValue = _string(field, 'optionValue');
    final optionIndex = _int(field, 'optionIndex');
    if (action == 'select' &&
        value.isEmpty &&
        (optionValue == null || optionValue.isEmpty) &&
        optionIndex == null) {
      throw ControlException(
        ControlErrorCode.badArguments,
        '下拉字段 [${record.ref}] 需要 value、optionValue 或 optionIndex 指定选项',
        hint: 'value 可以填选项文字；更精确的做法是 optionValue 或 optionIndex',
        details: {'ref': record.ref},
      );
    }
    return _FillField(
      ref: record.ref,
      label: record.label,
      value: value,
      action: action,
      replace: _bool(field, 'replace') ?? true,
      secret: _bool(field, 'secret') ?? false,
      optionValue: optionValue,
      optionIndex: optionIndex,
    );
  }

  ToolResult _fillFailure(
    ControlException error, {
    required List<_FillField> fields,
    required List<Map<String, Object?>> filled,
    required int failedIndex,
    required Delivery delivery,
    required bool pageReacted,
    required List<String> changes,
    required String urlBefore,
    required String urlAfter,
    required DateTime started,
  }) {
    final field = fields[failedIndex];
    final prefix = filled.isEmpty ? '' : '已填写 ${filled.length} 个字段，';
    return ToolResult(
      ok: false,
      error: ControlException(
        error.code,
        '$prefix第 ${failedIndex + 1} 个字段「${_displayName(field.label)}」'
            '填写失败：${error.message}',
        hint: error.hint ??
            '重新 snapshot 确认页面；已填好的字段不要重复填，从失败的字段继续',
        details: {
          ...?error.details,
          'filled': filled.length,
          'failedRef': field.ref,
        },
      ),
      data: {
        'fields': filled,
        'fieldCount': filled.length,
        'submitted': false,
        'failedAt': failedIndex,
        'url': urlAfter,
      },
      receipt: Receipt(
        tool: 'fill_form',
        delivery: filled.isEmpty ? Delivery.notDelivered : delivery,
        pageReacted: pageReacted,
        changes: changes.take(40).toList(),
        urlBefore: urlBefore,
        urlAfter: urlAfter,
        elapsed: DateTime.now().difference(started),
        note: '表单只填写了一部分，没有提交',
        details: {'fields': filled},
      ),
    );
  }

  static String _displayName(String label) {
    final match = RegExp(r'"([^"]*)"').firstMatch(label);
    final name = match?.group(1)?.trim();
    return name == null || name.isEmpty ? label : name;
  }

  static String _clip(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max - 1)}…';

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

/// One validated entry of `fill_form.fields`.
class _FillField {
  const _FillField({
    required this.ref,
    required this.label,
    required this.value,
    required this.action,
    required this.replace,
    required this.secret,
    this.optionValue,
    this.optionIndex,
  });

  final String ref;

  /// `textbox "姓名"`, kept from validation so a later error can name the field.
  final String label;

  final String value;

  /// `type` or `select`.
  final String action;

  final bool replace;
  final bool secret;
  final String? optionValue;
  final int? optionIndex;
}
