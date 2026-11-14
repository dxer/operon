import '../control/control.dart';
import '../control/protocol/results.dart';
import 'prompt.dart';
import 'ports.dart';

/// The name of the tool the agent calls to end a run.
const String doneToolName = 'done';

/// The name of the tool the agent calls to hand a question to the user.
const String askUserToolName = 'ask_user';

/// Builds the `tools` array an OpenAI-compatible endpoint expects.
///
/// The layer's catalogue is the only source: a tool that exists there is
/// offered here, and nothing else is. `screenshot` is left out unless the model
/// can see images, because a base64 PNG in a text-only request is money spent
/// on something that will be ignored.
List<Map<String, Object?>> buildToolSchemas({bool vision = false}) {
  return [
    for (final spec in controlToolCatalog)
      if (!spec.vision || vision)
        {
          'type': 'function',
          'function': {
            'name': spec.name,
            'description': spec.summary,
            'parameters': spec.toJsonSchema(),
          },
        },
    {
      'type': 'function',
      'function': {
        'name': doneToolName,
        'description': '结束任务并给出用户读到的答案。只在你看到每一步的结果之后调用。',
        'parameters': {
          'type': 'object',
          'properties': {
            'summary': {
              'type': 'string',
              'description': '给用户的最终答复：做成了什么、拿到了什么数据、还有什么没完成',
            },
            'outcome': {
              'type': 'string',
              'enum': ['success', 'partial', 'failed'],
              'description': 'success：亲眼确认目标达成；partial：做了一部分；failed：没做成',
            },
            'data': {
              'type': 'object',
              'description': '抽取或整理好的结构化结果（可选）。用户会在结果卡里看到并可复制。',
            },
          },
          'required': ['summary', 'outcome'],
          'additionalProperties': false,
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': askUserToolName,
        'description': '把一个问题交给用户回答，然后按回答继续。'
            '页面里找不到、或者只能由用户决定的事情用它，不要猜。',
        'parameters': {
          'type': 'object',
          'properties': {
            'question': {
              'type': 'string',
              'description': '要问用户的问题，一句话说清需要什么',
            },
          },
          'required': ['question'],
          'additionalProperties': false,
        },
      },
    },
  ];
}

/// Whether a tool changes the page. Unknown names are treated as writes: a
/// guard that lets an unknown tool through is worse than one extra question.
bool toolMutates(String name) {
  if (name == doneToolName || name == askUserToolName) return false;
  for (final spec in controlToolCatalog) {
    if (spec.name == name) return spec.mutates;
  }
  return true;
}

/// Renders one tool result into the text the model reads next turn.
///
/// Page-derived output is wrapped in the content boundary; a failure keeps the
/// error code, because "element gone" and "covered by an overlay" lead to
/// different next steps and the model must be able to tell them apart.
String renderToolResult(String tool, ToolResult result, {bool vision = false}) {
  if (!result.ok) {
    final error = result.error;
    if (error == null) return '失败：未知错误';
    final hint = error.hint;
    return '失败 [${error.code.name}]：${error.message}'
        '${hint == null ? '' : '\n怎么办：$hint'}';
  }

  final text = result.text ?? '';
  final buffer = StringBuffer();

  if (pageContentTools.contains(tool)) {
    buffer.writeln(wrapPageContent(text.isEmpty ? '(没有内容)' : text, source: tool));
  } else if (text.isNotEmpty) {
    buffer.writeln(text);
  }

  final receipt = result.receipt;
  if (receipt != null) {
    buffer.writeln('回执：${receipt.summary}');
    if (receipt.changes.isNotEmpty) {
      buffer.writeln('变化：');
      for (final line in receipt.changes.take(20)) {
        buffer.writeln(line);
      }
    }
    final note = receipt.note;
    if (note != null && note.isNotEmpty) buffer.writeln('注意：$note');
  }

  final data = result.data;
  if (data != null) {
    final omitted = data['omitted'];
    if (omitted is List && omitted.isNotEmpty) {
      buffer.write('未显示的部分：${omitted.join('；')}');
    }
    final truncated = data['truncated'];
    if (truncated == true) buffer.write('（内容已截断，需要更多请滚动后重新读取）');
    if (data['image'] != null && !vision) {
      buffer.write('（截图已获取；当前模型看不到图片，已忽略）');
    }
  }

  final rendered = buffer.toString().trim();
  return rendered.isEmpty ? '成功（没有需要报告的内容）' : rendered;
}

/// One line for the log and the step card: what the model asked for, in words.
String describeToolCall(String name, Map<String, Object?> args) {
  String arg(String key) => args[key]?.toString() ?? '';
  switch (name) {
    case 'snapshot':
      return '读取页面';
    case 'read':
      return '读取文字内容';
    case 'find':
      final query = arg('query');
      final role = arg('role');
      return '查找控件${query.isEmpty ? (role.isEmpty ? '' : '（$role）') : '「$query」'}';
    case 'screenshot':
      return '截图';
    case 'click':
      return '点击 [${arg('ref')}]';
    case 'type':
      final secret = args['secret'] == true;
      final submit = args['submit'] == true;
      return '输入${secret ? '敏感内容' : '文字'}到 [${arg('ref')}]${submit ? ' 并提交' : ''}';
    case 'press':
      return '按键 ${arg('key')}';
    case 'scroll':
      return '滚动 ${arg('direction').isEmpty ? 'down' : arg('direction')}';
    case 'navigate':
      return '打开 ${arg('url')}';
    case 'wait':
      final ref = arg('ref');
      if (ref.isNotEmpty) return '等待 [$ref] 出现';
      final ms = arg('ms');
      return ms.isEmpty ? '等待页面稳定' : '等待 $ms ms';
    case 'handle_dialog':
      return args['accept'] == true ? '接受页面弹窗' : '取消页面弹窗';
    case doneToolName:
      return '结束任务';
    case askUserToolName:
      final question = arg('question');
      return '询问用户${question.isEmpty ? '' : '：$question'}';
    default:
      return name;
  }
}

/// The `done` arguments, parsed once so the loop and the runner agree.
class DoneReport {
  const DoneReport({required this.summary, required this.outcome, this.data});

  final String summary;

  /// `success`, `partial` or `failed`.
  final String outcome;

  /// Structured results, when the model produced any.
  final Object? data;

  static DoneReport fromArgs(Map<String, Object?> args) {
    final summary = (args['summary'] ?? '').toString().trim();
    final rawOutcome = (args['outcome'] ?? '').toString().trim().toLowerCase();
    final outcome = const {'success', 'partial', 'failed'}.contains(rawOutcome)
        ? rawOutcome
        : 'partial';
    final data = args['data'];
    return DoneReport(
      summary: summary.isEmpty ? '（模型没有给出总结）' : summary,
      outcome: outcome,
      data: data is Map || data is List ? data : null,
    );
  }
}

/// The `user` message that opens every run.
Map<String, Object?> goalMessage(String goal) => {
      'role': 'user',
      'content': goal,
    };

/// The assistant message that carries a reply and its calls.
Map<String, Object?> assistantMessage(LlmTurn turn) => {
      'role': 'assistant',
      'content': turn.content ?? '',
      if (turn.calls.isNotEmpty)
        'tool_calls': [
          for (final call in turn.calls)
            {
              'id': call.id,
              'type': 'function',
              'function': {
                'name': call.name,
                'arguments': call.rawArguments.isEmpty
                    ? stableJson(call.args)
                    : call.rawArguments,
              },
            },
        ],
    };

/// The message that answers one call.
Map<String, Object?> toolMessage(String callId, String content) => {
      'role': 'tool',
      'tool_call_id': callId,
      'content': content,
    };

/// Minimal stable JSON for the arguments round trip.
String stableJson(Object? value) {
  try {
    // JsonEncoder with sorted keys, so the same arguments always render the same.
    return _encode(value);
  } catch (_) {
    return '$value';
  }
}

String _encode(Object? value) {
  if (value == null) return 'null';
  if (value is num || value is bool) return '$value';
  if (value is String) return '"${value.replaceAll('"', '\\"')}"';
  if (value is List) return '[${value.map(_encode).join(',')}]';
  if (value is Map) {
    final keys = value.keys.map((key) => '$key').toList()..sort();
    return '{${keys.map((key) => '${_encode(key)}:${_encode(value[key])}').join(',')}}';
  }
  return '"$value"';
}
