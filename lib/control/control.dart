import 'interaction/input.dart';
import 'protocol/errors.dart';
import 'protocol/results.dart';
import 'transport/devtools_socket.dart';
import 'transport/endpoint.dart' show SocketConnector;
import 'session.dart';

/// The value types a tool parameter can take, and the JSON Schema type for it.
enum ControlParamType { text, number, boolean, choice }

/// One tool parameter: the name the model must use, what it means, and whether
/// it is required.
class ControlParam {
  const ControlParam({
    required this.name,
    required this.description,
    this.type = ControlParamType.text,
    this.required = false,
    this.options = const [],
  });

  final String name;
  final String description;
  final ControlParamType type;
  final bool required;

  /// Allowed values for [ControlParamType.choice].
  final List<String> options;

  Map<String, Object?> toJsonSchema() => {
        'type': switch (type) {
          ControlParamType.text || ControlParamType.choice => 'string',
          ControlParamType.number => 'number',
          ControlParamType.boolean => 'boolean',
        },
        'description': description,
        if (options.isNotEmpty) 'enum': options,
      };
}

/// One tool the control layer offers, in the shape both a prompt and an
/// OpenAI-compatible tool definition need.
class ControlToolSpec {
  const ControlToolSpec({
    required this.name,
    required this.summary,
    this.params = const [],
    this.mutates = false,
    this.vision = false,
  });

  final String name;
  final String summary;
  final List<ControlParam> params;

  /// Reading tools never change the page, so a batch of them can run at once.
  final bool mutates;

  /// Only useful to a model that can see images.
  final bool vision;

  /// The JSON Schema an OpenAI-compatible endpoint expects in `tools`.
  Map<String, Object?> toJsonSchema() => {
        'type': 'object',
        'properties': {
          for (final param in params) param.name: param.toJsonSchema(),
        },
        if (params.any((param) => param.required))
          'required': params.where((param) => param.required).map((param) => param.name).toList(),
        'additionalProperties': false,
      };
}

/// The catalogue. The agent prompt, the diagnostics screen and any future flow
/// editor read this one list, so a tool cannot exist in one place and be
/// missing in another.
const List<ControlToolSpec> controlToolCatalog = [
  ControlToolSpec(
    name: 'snapshot',
    summary: '读取当前页面的可操作元素（带 ref）与文字。动作之前先看；页面变化之后再看。',
    params: [
      ControlParam(
        name: 'content',
        description: '是否同时返回页面文字，默认 true',
        type: ControlParamType.boolean,
      ),
    ],
  ),
  ControlToolSpec(
    name: 'read',
    summary: '只读取页面文字，不列控件；用于总结与抽取。',
    params: [
      ControlParam(
        name: 'limit',
        description: '最多返回多少段，默认 14',
        type: ControlParamType.number,
      ),
    ],
  ),
  ControlToolSpec(
    name: 'find',
    summary: '按名称或 role 找控件，返回带 ref 的匹配项。元素多、名字相似时用它，不要靠猜。',
    params: [
      ControlParam(name: 'query', description: '名称片段，不区分大小写'),
      ControlParam(name: 'role', description: '限定 role，如 button / link / textbox'),
      ControlParam(
        name: 'exact',
        description: '名称必须完全相等，默认 false',
        type: ControlParamType.boolean,
      ),
      ControlParam(
        name: 'limit',
        description: '最多返回几条，默认 20',
        type: ControlParamType.number,
      ),
    ],
  ),
  ControlToolSpec(
    name: 'screenshot',
    summary: '截取当前页面（PNG）。用于判断布局与遮挡；看不到图片的模型不要调用。',
    params: [
      ControlParam(
        name: 'fullPage',
        description: '截取整页而非可视区，默认 false',
        type: ControlParamType.boolean,
      ),
    ],
    vision: true,
  ),
  ControlToolSpec(
    name: 'click',
    summary: '点击一个 ref。派发的是浏览器真实输入事件，不是页面脚本合成的。',
    params: [
      ControlParam(name: 'ref', description: '快照里的 ref，如 a3', required: true),
      ControlParam(
        name: 'mode',
        description: '派发方式',
        type: ControlParamType.choice,
        options: ['auto', 'touch', 'mouse'],
      ),
    ],
    mutates: true,
  ),
  ControlToolSpec(
    name: 'type',
    summary: '向输入框或可编辑区域输入文字。走浏览器编辑管线，受控输入也会同步。',
    params: [
      ControlParam(name: 'ref', description: '输入框的 ref', required: true),
      ControlParam(name: 'text', description: '要输入的文字', required: true),
      ControlParam(
        name: 'replace',
        description: '先清空原有内容，默认 false',
        type: ControlParamType.boolean,
      ),
      ControlParam(
        name: 'submit',
        description: '输入后按回车，默认 false',
        type: ControlParamType.boolean,
      ),
      ControlParam(
        name: 'secret',
        description: '内容是密码或验证码，不写日志，默认 false',
        type: ControlParamType.boolean,
      ),
    ],
    mutates: true,
  ),
  ControlToolSpec(
    name: 'select',
    summary: '在原生下拉框里选一项。系统弹层无法用鼠标驱动，这里直接设置选中项并触发 change 事件。',
    params: [
      ControlParam(name: 'ref', description: '下拉框的 ref', required: true),
      ControlParam(name: 'optionLabel', description: '选项上显示的文字，可以是片段'),
      ControlParam(name: 'optionValue', description: '选项的 value，比 label 更精确'),
      ControlParam(
        name: 'optionIndex',
        description: '选项下标，从 0 开始',
        type: ControlParamType.number,
      ),
    ],
    mutates: true,
  ),
  ControlToolSpec(
    name: 'hover',
    summary: '把指针移到元素上并停住，用于只有悬停才会展开的菜单。',
    params: [
      ControlParam(name: 'ref', description: '要悬停的 ref', required: true),
    ],
    mutates: true,
  ),
  ControlToolSpec(
    name: 'press',
    summary: '在焦点元素上按一个键。',
    params: [
      ControlParam(
        name: 'key',
        description: '按键名',
        required: true,
        type: ControlParamType.choice,
        options: [
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
        ],
      ),
    ],
    mutates: true,
  ),
  ControlToolSpec(
    name: 'scroll',
    summary: '滚动页面或某个容器，返回滚动后的新内容。',
    params: [
      ControlParam(
        name: 'direction',
        description: '方向',
        type: ControlParamType.choice,
        options: ['down', 'up'],
      ),
      ControlParam(name: 'amount', description: '像素距离，默认约 0.8 屏', type: ControlParamType.number),
      ControlParam(name: 'ref', description: '要滚动的容器 ref；省略则滚页面'),
    ],
    mutates: true,
  ),
  ControlToolSpec(
    name: 'navigate',
    summary: '打开一个网址并等待加载完成。打开后必须重新 snapshot。',
    params: [
      ControlParam(name: 'url', description: '网址', required: true),
    ],
    mutates: true,
  ),
  ControlToolSpec(
    name: 'back',
    summary: '回到上一页。保留历史、表单和 SPA 状态，比重新 navigate 更好。',
    params: [
      ControlParam(
        name: 'steps',
        description: '回退几步，默认 1',
        type: ControlParamType.number,
      ),
    ],
    mutates: true,
  ),
  ControlToolSpec(
    name: 'forward',
    summary: '前进到下一页（回退之后）。',
    params: [
      ControlParam(
        name: 'steps',
        description: '前进几步，默认 1',
        type: ControlParamType.number,
      ),
    ],
    mutates: true,
  ),
  ControlToolSpec(
    name: 'tabs',
    summary: '列出应用里打开的所有标签页，标出当前正在操作的那一个。',
    params: [],
  ),
  ControlToolSpec(
    name: 'switch_tab',
    summary: '切换到另一个标签页。切换后必须重新 snapshot，旧的 ref 全部失效。',
    params: [
      ControlParam(
        name: 'tabId',
        description: 'tabs 返回的 id；也可以传列表序号（从 0 开始）',
        required: true,
      ),
    ],
    mutates: true,
  ),
  ControlToolSpec(
    name: 'upload',
    summary: '把设备上的文件交给页面里的文件选择控件。路径必须是真实存在的绝对路径。',
    params: [
      ControlParam(name: 'ref', description: '文件控件的 ref', required: true),
      ControlParam(
        name: 'files',
        description: '文件绝对路径列表，用逗号分隔',
        required: true,
      ),
    ],
    mutates: true,
  ),
  ControlToolSpec(
    name: 'wait',
    summary: '等某个 ref 出现、等一段时间，或等页面稳定。',
    params: [
      ControlParam(name: 'ref', description: '等这个 ref 出现'),
      ControlParam(name: 'ms', description: '固定等待毫秒数，上限 10000', type: ControlParamType.number),
    ],
  ),
  ControlToolSpec(
    name: 'handle_dialog',
    summary: '处理页面弹窗。弹窗打开时页面冻结，其它工具都会失败。',
    params: [
      ControlParam(
        name: 'accept',
        description: 'true 接受 / false 取消',
        type: ControlParamType.boolean,
        required: true,
      ),
      ControlParam(name: 'promptText', description: 'prompt 弹窗要输入的文字'),
    ],
    mutates: true,
  ),
];

/// The control layer as one callable object.
///
/// A caller picks a tool by name and passes plain arguments, which keeps the
/// same call shape for the agent, a recorded flow, and a diagnostic.
class Control {
  Control._(this._session, {required SocketConnector connect}) : _connect = connect;

  static Future<Control> attach({
    String? urlHint,
    String? targetId,
    DevToolsAddress? address,
    SocketConnector? connect,
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

  /// Notified before an input is dispatched, with the point it lands on.
  ///
  /// The layer decides the point, so the overlay can never animate a place the
  /// click did not go.
  void Function(double x, double y, String label)? get onGesture => session.onGesture;

  set onGesture(void Function(double x, double y, String label)? value) =>
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
    final previous = _session;
    final gesture = previous.onGesture;
    final next = await ControlSession.attach(
      connect: _connect,
      targetId: target.id,
    );
    next.onGesture = gesture;
    await previous.detach();
    _session = next;
    return ToolResult(
      ok: true,
      text: '已切换到 ${target.title.trim().isEmpty ? target.url : target.title}（${target.url}），ref 需要重新 snapshot',
      data: {'id': target.id, 'url': target.url, 'title': target.title},
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
      throw const ControlException(
        ControlErrorCode.internal,
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
