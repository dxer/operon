import 'dart:convert';

import '../config/tool_catalog.dart';
import '../models/agent_action.dart';
import '../models/skill.dart';
import '../utils/url_utils.dart';

/// Records a real agent demonstration into a replayable flow skill.
///
/// Anchors are never authored by the model: every locator must come from
/// [WebViewControllerWrapper.getElementLocator], which builds a candidate
/// chain from the live DOM element the agent actually used. Actions without a
/// resolvable locator are not recorded, so a generated skill cannot contain a
/// guessed selector.
class SkillRecordingSession {
  SkillRecordingSession({
    required this.sampleContent,
    String? currentHost,
  }) : host = normalizeHost(currentHost ?? '');

  final String sampleContent;

  String host;

  final List<SkillStep> _steps = [];
  final List<SkillInput> _inputs = [];
  final Set<String> _usedIds = {};

  bool _contentInputAdded = false;
  bool _endedWithDryRun = false;
  String? _dryRunLabel;

  List<SkillStep> get steps => List.unmodifiable(_steps);
  List<SkillInput> get inputs => List.unmodifiable(_inputs);
  int get stepCount => _steps.length;
  bool get endedWithDryRun => _endedWithDryRun;

  /// True when the agent is about to submit the demonstration content (not a
  /// search query or another incidental input).
  bool isSampleText(String? text) {
    final sample = sampleContent.trim();
    return sample.isNotEmpty && text != null && text.trim() == sample;
  }

  bool get hasContentInput => _contentInputAdded;

  /// Records one successfully executed action.
  ///
  /// [dryRun] is used for the terminal submit: the element is resolved and
  /// recorded, but the action is deliberately never dispatched.
  bool capture(
    AgentAction action, {
    Map<String, dynamic>? locator,
    String? elementText,
    String? macroSelector,
    bool dryRun = false,
    String intent = 'auto',
  }) {
    final label = (elementText ?? '').trim();
    final clean = _cleanLocator(locator, macroSelector);

    switch (action.action) {
      case ActionType.click:
        if (clean == null) return false;
        return _append(
          tool: 'page.click',
          name: dryRun
              ? '点击「${_shortLabel(label)}」提交'
              : '点击「${_shortLabel(label)}」',
          params: {
            'locator': clean,
            if (dryRun) 'intent': intent,
          },
          dryRun: dryRun,
          dryRunLabel: label,
        );
      case ActionType.type:
        if (clean == null) return false;
        final text = _templateText(action.text);
        if (text == null) return false;
        return _append(
          tool: 'page.type',
          name: label.isEmpty ? '输入内容' : '输入到「${_shortLabel(label)}」',
          params: {
            'locator': clean,
            'text': text,
            'clear': true,
          },
        );
      case ActionType.pressKey:
        final key = (action.key ?? 'Enter').trim();
        if (key.isEmpty) return false;
        return _append(
          tool: 'page.press_key',
          name: '按下 $key',
          params: {
            'key': key,
            if (clean != null) 'locator': clean,
          },
          dryRun: dryRun,
          dryRunLabel: label.isEmpty ? key : label,
        );
      case ActionType.selectOption:
        if (clean == null) return false;
        final value = (action.selectValue ?? '').trim();
        if (value.isEmpty) return false;
        return _append(
          tool: 'page.select',
          name: label.isEmpty ? '选择下拉项' : '在「${_shortLabel(label)}」选择',
          params: {
            'locator': clean,
            'value': value,
          },
        );
      case ActionType.hover:
        if (clean == null) return false;
        return _append(
          tool: 'page.hover',
          name: '悬停「${_shortLabel(label)}」',
          params: {'locator': clean},
        );
      case ActionType.scroll:
        return _append(
          tool: 'page.scroll',
          name: action.direction == 'up' ? '向上滚动' : '向下滚动',
          params: {'direction': action.direction == 'up' ? 'up' : 'down'},
        );
      case ActionType.navigate:
        final url = (action.url ?? '').trim();
        if (url.isEmpty) return false;
        final recordedHost = hostOf(url);
        // Keep the page the demonstration started from: that is the site the
        // skill is scoped to. Only fill in from a navigation when the start
        // page had no host.
        if (host.isEmpty && recordedHost.isNotEmpty) host = recordedHost;
        return _append(
          tool: 'page.open',
          name: '打开网页',
          params: {'url': url, 'waitMs': 800},
        );
      case ActionType.goBack:
        return _append(
          tool: 'page.back',
          name: '返回上一页',
          params: const {},
        );
      case ActionType.wait:
        final ms = action.duration ?? 1000;
        if (ms <= 0) return false;
        return _append(
          tool: 'page.wait',
          name: '等待 ${ms}ms',
          params: {'ms': ms},
        );
      case ActionType.extractData:
      case ActionType.finish:
      case ActionType.unknown:
        return false;
    }
  }

  SkillDraft? buildDraft({
    required String name,
    required String description,
  }) {
    if (_steps.isEmpty) return null;
    // The demonstration text must never be baked into the skill: replaying it
    // would post the same sentence every run. When no sample was given, the
    // one literal text typed before the recorded submit stands in for it.
    _promoteContentText();
    final writeSteps = _steps.where((step) {
      return ToolCatalog.find(step.tool)?.isWrite == true;
    }).length;
    final hasWrites = writeSteps > 0;

    return SkillDraft(
      name: name.trim().isEmpty ? deriveName(description) : name.trim(),
      description: description.trim(),
      kind: SkillKind.flow,
      inputs: List<SkillInput>.from(_inputs),
      // Flow execution ignores instructions, but SKILL.md uses them as the
      // human-readable notes (dry-run submit, content input, known limits).
      instructions: _notes(hasWrites),
      steps: List<SkillStep>.from(_steps),
      policy: SkillPolicy(
        maxSteps: _steps.length + 4,
        maxSideEffects: hasWrites ? writeSteps : 0,
        maxItems: 1,
        maxDurationMs: 300000,
        confirmWrites: true,
        confirmDestructive: true,
        uniqueContent: _contentInputAdded,
        uniqueTarget: writeSteps > 1,
        hostScope: hasWrites && host.isNotEmpty
            ? SkillHostScope.list
            : SkillHostScope.any,
        allowedHosts: host.isEmpty ? const [] : [host],
      ),
      notes: _notes(hasWrites),
    );
  }

  String summary() {
    if (_steps.isEmpty) return '没有记录到可执行步骤。';
    return [
      '录制了 ${_steps.length} 步：',
      ..._steps.map((step) => '- ${step.name} (${step.tool})'),
    ].join('\n');
  }

  String _notes(bool hasWrites) {
    final lines = <String>[
      '定位器由真实页面元素生成，并在演示时实际解析过。',
    ];
    if (_endedWithDryRun) {
      final label = _dryRunLabel?.trim();
      lines.add(
        '提交步骤「${label == null || label.isEmpty ? '发布' : label}」'
        '只做了定位，没有真正点击；运行技能时仍会逐步确认。',
      );
    } else if (hasWrites) {
      lines.add('没有记录到明确的提交步骤；请在编辑器中检查流程是否完整。');
    }
    if (_contentInputAdded) {
      lines.add('演示时输入的示例内容已替换为 {{inputs.content}}。');
    }
    if (_steps.every((step) => step.tool != 'page.open')) {
      lines.add('技能从运行时的当前页面开始；如需固定入口，请添加“打开网页”步骤。');
    }
    return lines.join('\n');
  }

  String? _templateText(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return null;
    final sample = sampleContent.trim();
    if (sample.isNotEmpty && text == sample) {
      _ensureContentInput();
      return '{{inputs.content}}';
    }
    // Literal braces must not be interpreted as template bindings.
    return text.replaceAll('{{', r'\{{');
  }

  /// Turns the demonstration-authored body into `{{inputs.content}}`.
  ///
  /// Only applies to recorded writes with exactly one literal text: a search
  /// term plus a reply body are different things, and guessing which one the
  /// user wants to vary would be worse than leaving both literal.
  void _promoteContentText() {
    if (_contentInputAdded) return;
    final writeSteps = _steps.where((step) {
      return ToolCatalog.find(step.tool)?.isWrite == true;
    }).length;
    if (writeSteps == 0) return;

    final literal = _steps.where((step) {
      if (step.tool != 'page.type') return false;
      final text = step.params['text']?.toString().trim() ?? '';
      return text.isNotEmpty && !text.contains('{{');
    }).toList();
    if (literal.length != 1) return;

    final index = _steps.indexOf(literal.single);
    final example = literal.single.params['text'].toString();
    _steps[index] = literal.single.copyWith(
      params: {...literal.single.params, 'text': '{{inputs.content}}'},
    );
    _ensureContentInput(hint: '示例：${_shortLabel(example, 80)}');
  }

  void _ensureContentInput({String? hint}) {
    if (_contentInputAdded) return;
    _contentInputAdded = true;
    _inputs.add(SkillInput(
      key: 'content',
      label: '内容',
      type: SkillInputType.multiline,
      required: true,
      hint: hint ??
          (sampleContent.trim().isEmpty
              ? '运行时填写要输入或发布的内容'
              : '示例：${_shortLabel(sampleContent.trim(), 80)}'),
    ));
  }

  /// Keeps only the portable parts of a JS locator. The fingerprint is
  /// intentionally dropped: it contains surrounding text, so replaying it on
  /// a different feed item could prefer the wrong element.
  Map<String, dynamic>? _cleanLocator(
    Map<String, dynamic>? locator,
    String? macroSelector,
  ) {
    Map<String, dynamic>? source;
    if (locator != null) {
      final nested = locator['locator'];
      source = nested is Map
          ? Map<String, dynamic>.from(nested)
          : Map<String, dynamic>.from(locator);
    }
    if (source == null || source['candidates'] is! List) {
      final fallback = (macroSelector ?? '').trim();
      if (fallback.isEmpty) return null;
      final isXpath = fallback.startsWith('xpath://');
      return {
        'candidates': [
          {
            'type': isXpath ? 'xpath' : 'css',
            'value': isXpath ? fallback.substring(8) : fallback,
          },
        ],
        'requireUnique': false,
      };
    }

    final candidates = (source['candidates'] as List)
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) {
      final type = item['type']?.toString() ?? '';
      if (type == 'role') {
        return (item['role']?.toString() ?? '').isNotEmpty ||
            (item['name']?.toString() ?? '').isNotEmpty;
      }
      return (item['value']?.toString() ?? '').isNotEmpty;
    }).toList();
    if (candidates.isEmpty) return null;

    final result = <String, dynamic>{
      'candidates': candidates,
      'requireUnique': source['requireUnique'] == true,
    };
    final nth = source['nth'];
    if (nth is num && nth >= 0) {
      result['nth'] = nth.toInt();
    }
    return result;
  }

  bool _append({
    required String tool,
    required String name,
    required Map<String, dynamic> params,
    bool dryRun = false,
    String? dryRunLabel,
  }) {
    // Retrying the same action must not add a duplicate step.
    if (_steps.isNotEmpty &&
        _steps.last.tool == tool &&
        jsonEncode(_steps.last.params) == jsonEncode(params)) {
      return false;
    }

    final id = _nextId(tool);
    _steps.add(SkillStep(
      id: id,
      name: name.trim().isEmpty ? tool : name.trim(),
      tool: tool,
      params: params,
    ));
    if (dryRun) {
      _endedWithDryRun = true;
      _dryRunLabel =
          (dryRunLabel ?? '').trim().isEmpty ? null : dryRunLabel!.trim();
    }
    return true;
  }

  String _nextId(String tool) {
    final base = tool.replaceFirst('page.', '').replaceAll('.', '_');
    var id = 'step_${_steps.length + 1}_$base';
    var suffix = 2;
    while (!_usedIds.add(id)) {
      id = 'step_${_steps.length + 1}_${base}_$suffix';
      suffix++;
    }
    return id;
  }

  static String _shortLabel(String value, [int max = 28]) {
    final text = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return '元素';
    return text.length <= max ? text : '${text.substring(0, max)}…';
  }

  /// Turns a user description into a usable default name.
  static String deriveName(String description) {
    var text = description.trim().split(RegExp(r'[\n。；;]')).first.trim();
    text = text.replaceFirst(
      RegExp(r'^(请|帮我|帮忙|我要|我想|需要|创建一个|创建|做一个|生成一个|生成)\s*'),
      '',
    );
    text = text.replaceFirst(RegExp(r'的?技能$'), '').trim();
    if (text.isEmpty) return '录制技能';
    return text.length <= 40 ? text : '${text.substring(0, 40)}…';
  }
}
