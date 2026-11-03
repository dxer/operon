import '../models/tool_descriptor.dart';

/// The single source of truth for atomic capabilities.
///
/// P1 tools are wired to the WebView / LLM in later steps. Declaring them here
/// first lets the validator, editor and AI authoring prompt share one catalog.
class ToolCatalog {
  ToolCatalog._();

  static const List<ToolDescriptor> all = [
    // ---------------------------------------------------------------- page
    ToolDescriptor(
      id: 'page.open',
      name: '打开网页',
      description: '打开指定 URL，并等待页面稳定。',
      risk: ToolRisk.navigate,
      idempotent: true,
      timeout: Duration(seconds: 30),
      params: [
        ToolParam(
            key: 'url', label: '网址', type: ToolParamType.text, required: true),
        ToolParam(
          key: 'waitMs',
          label: '打开后等待',
          type: ToolParamType.number,
          defaultValue: 800,
        ),
      ],
      outputSchema: {
        'url': 'string',
        'title': 'string',
      },
    ),
    ToolDescriptor(
      id: 'page.refresh',
      name: '刷新网页',
      description: '刷新当前页面，等待 DOM 稳定。',
      risk: ToolRisk.navigate,
      idempotent: true,
      timeout: Duration(seconds: 30),
      params: [
        ToolParam(
          key: 'waitMs',
          label: '刷新后等待',
          type: ToolParamType.number,
          defaultValue: 800,
        ),
      ],
      outputSchema: {'url': 'string'},
    ),
    ToolDescriptor(
      id: 'page.back',
      name: '网页后退',
      description: '返回上一页。',
      risk: ToolRisk.navigate,
      idempotent: true,
      timeout: Duration(seconds: 15),
      outputSchema: {'url': 'string'},
    ),
    ToolDescriptor(
      id: 'page.read',
      name: '读取页面',
      description: '读取当前页面的标题、URL 和正文。',
      risk: ToolRisk.read,
      params: [
        ToolParam(
          key: 'maxChars',
          label: '最多字符',
          type: ToolParamType.number,
          defaultValue: 12000,
        ),
      ],
      outputSchema: {
        'title': 'string',
        'url': 'string',
        'content': 'string',
        'links': 'string[]',
      },
    ),
    ToolDescriptor(
      id: 'page.read_region',
      name: '读取区域',
      description: '按定位器读取页面区域，支持文本或条目列表。',
      risk: ToolRisk.read,
      params: [
        ToolParam(
          key: 'locator',
          label: '目标区域',
          type: ToolParamType.locator,
          required: true,
          hint: '优先使用文字、role 或语义描述，CSS 作为补充。',
        ),
        ToolParam(
          key: 'mode',
          label: '读取方式',
          type: ToolParamType.select,
          defaultValue: 'text',
          options: ['text', 'items'],
        ),
        ToolParam(
          key: 'limit',
          label: '最多条数',
          type: ToolParamType.number,
          defaultValue: 20,
        ),
        ToolParam(
          key: 'maxChars',
          label: '最多字符',
          type: ToolParamType.number,
          defaultValue: 12000,
        ),
        ToolParam(
          key: 'itemLocator',
          label: '条目定位器',
          type: ToolParamType.locator,
          hint: '留空时自动尝试识别重复条目。',
        ),
        ToolParam(
          key: 'fields',
          label: '字段映射（高级）',
          type: ToolParamType.json,
        ),
      ],
      outputSchema: {
        'items': 'object[]',
        'count': 'number',
        'truncated': 'boolean',
      },
    ),
    ToolDescriptor(
      id: 'page.wait',
      name: '等待',
      description: '等待固定时间、元素出现/消失，或等待 DOM 稳定。',
      risk: ToolRisk.read,
      params: [
        ToolParam(
          key: 'ms',
          label: '等待毫秒',
          type: ToolParamType.number,
          defaultValue: 1000,
        ),
        ToolParam(key: 'locator', label: '等待元素', type: ToolParamType.locator),
        ToolParam(
          key: 'state',
          label: '元素状态',
          type: ToolParamType.select,
          defaultValue: 'visible',
          options: ['visible', 'hidden', 'attached'],
        ),
        ToolParam(
          key: 'timeoutMs',
          label: '超时毫秒',
          type: ToolParamType.number,
          defaultValue: 10000,
        ),
      ],
      outputSchema: {'waited': 'number'},
    ),
    ToolDescriptor(
      id: 'page.scroll',
      name: '滚动页面',
      description: '按方向滚动，或把指定元素滚动到视口。',
      risk: ToolRisk.navigate,
      params: [
        ToolParam(
          key: 'direction',
          label: '方向',
          type: ToolParamType.select,
          defaultValue: 'down',
          options: ['down', 'up'],
        ),
        ToolParam(key: 'amount', label: '滚动距离', type: ToolParamType.number),
        ToolParam(key: 'locator', label: '滚动到元素', type: ToolParamType.locator),
        ToolParam(
          key: 'align',
          label: '对齐方式',
          type: ToolParamType.select,
          defaultValue: 'center',
          options: ['start', 'center', 'end'],
        ),
      ],
      outputSchema: {'scrollY': 'number'},
    ),

    // --------------------------------------------------------------- write
    ToolDescriptor(
      id: 'page.click',
      name: '点击元素',
      description: '解析定位器后点击目标；发送、支付、删除类目标会升级为高风险。',
      risk: ToolRisk.write,
      idempotent: false,
      requiresConfirmation: true,
      params: [
        ToolParam(
          key: 'locator',
          label: '目标元素',
          type: ToolParamType.locator,
          required: true,
        ),
        ToolParam(
          key: 'waitAfterMs',
          label: '点击后等待',
          type: ToolParamType.number,
          defaultValue: 800,
        ),
        ToolParam(
          key: 'expectNavigation',
          label: '预期会跳转',
          type: ToolParamType.boolean,
          defaultValue: false,
        ),
      ],
      outputSchema: {'clicked': 'boolean', 'url': 'string'},
    ),
    ToolDescriptor(
      id: 'page.type',
      name: '输入文本',
      description: '在输入框中输入文本，可选清空和回车提交。',
      risk: ToolRisk.write,
      idempotent: false,
      requiresConfirmation: true,
      params: [
        ToolParam(
          key: 'locator',
          label: '输入框',
          type: ToolParamType.locator,
          required: true,
        ),
        ToolParam(
          key: 'text',
          label: '文本',
          type: ToolParamType.multiline,
          required: true,
        ),
        ToolParam(
          key: 'clear',
          label: '先清空',
          type: ToolParamType.boolean,
          defaultValue: true,
        ),
        ToolParam(
          key: 'submit',
          label: '输入后回车',
          type: ToolParamType.boolean,
          defaultValue: false,
        ),
        ToolParam(
          key: 'secret',
          label: '密钥内容',
          type: ToolParamType.boolean,
          defaultValue: false,
        ),
      ],
      outputSchema: {'typed': 'boolean', 'submitted': 'boolean'},
    ),
    ToolDescriptor(
      id: 'page.press_key',
      name: '按键',
      description: '按下回车、Tab、Esc 等按键。',
      risk: ToolRisk.write,
      idempotent: false,
      requiresConfirmation: true,
      params: [
        ToolParam(
          key: 'key',
          label: '按键',
          type: ToolParamType.select,
          required: true,
          options: [
            'Enter',
            'Tab',
            'Escape',
            'Backspace',
            'ArrowDown',
            'ArrowUp',
          ],
        ),
        ToolParam(key: 'locator', label: '目标元素', type: ToolParamType.locator),
      ],
      outputSchema: {'pressed': 'string'},
    ),
    ToolDescriptor(
      id: 'page.select',
      name: '下拉选择',
      description: '在 select 元素中选择指定值。',
      risk: ToolRisk.write,
      idempotent: false,
      requiresConfirmation: true,
      params: [
        ToolParam(
          key: 'locator',
          label: '下拉框',
          type: ToolParamType.locator,
          required: true,
        ),
        ToolParam(
          key: 'value',
          label: '选项',
          type: ToolParamType.text,
          required: true,
        ),
      ],
      outputSchema: {'selected': 'string'},
    ),
    ToolDescriptor(
      id: 'page.hover',
      name: '悬停',
      description: '将鼠标移动到指定元素上。',
      risk: ToolRisk.write,
      idempotent: true,
      requiresConfirmation: false,
      params: [
        ToolParam(
          key: 'locator',
          label: '目标元素',
          type: ToolParamType.locator,
          required: true,
        ),
      ],
      outputSchema: {'hovered': 'boolean'},
    ),

    // ------------------------------------------------------------------ ai
    ToolDescriptor(
      id: 'ai.generate',
      name: 'AI 处理',
      description: '用模型生成文本或结构化 JSON；页面数据只能作为 data 传入。',
      risk: ToolRisk.read,
      cost: ToolCost.llm,
      availability: ToolAvailability.background,
      timeout: Duration(seconds: 60),
      params: [
        ToolParam(
          key: 'prompt',
          label: '提示词',
          type: ToolParamType.multiline,
          required: true,
        ),
        ToolParam(
          key: 'data',
          label: '输入数据',
          type: ToolParamType.json,
          hint: '页面内容放在这里，不要直接拼进 prompt。',
        ),
        ToolParam(
          key: 'format',
          label: '输出格式',
          type: ToolParamType.select,
          defaultValue: 'text',
          options: ['text', 'json'],
        ),
        ToolParam(key: 'schema', label: 'JSON 结构', type: ToolParamType.json),
        ToolParam(
          key: 'temperature',
          label: '温度',
          type: ToolParamType.number,
          defaultValue: 0.2,
        ),
      ],
      outputSchema: {'text': 'string', 'json': 'object'},
    ),
    ToolDescriptor(
      id: 'ai.extract',
      name: 'AI 结构化抽取',
      description: '从文本或页面数据中抽取结构化字段。',
      risk: ToolRisk.read,
      cost: ToolCost.llm,
      availability: ToolAvailability.background,
      timeout: Duration(seconds: 60),
      params: [
        ToolParam(
          key: 'prompt',
          label: '抽取要求',
          type: ToolParamType.multiline,
          required: true,
        ),
        ToolParam(
          key: 'data',
          label: '输入数据',
          type: ToolParamType.json,
          required: true,
        ),
        ToolParam(
          key: 'schema',
          label: '字段结构',
          type: ToolParamType.json,
          required: true,
        ),
      ],
      outputSchema: {'json': 'object'},
    ),
    ToolDescriptor(
      id: 'agent.task',
      name: '交给 Agent',
      description: '把无法固定描述的一步交给受限 Agent，带工具白名单和步数预算。',
      risk: ToolRisk.write,
      cost: ToolCost.llm,
      idempotent: false,
      requiresConfirmation: true,
      timeout: Duration(minutes: 3),
      params: [
        ToolParam(
          key: 'goal',
          label: '子任务目标',
          type: ToolParamType.multiline,
          required: true,
        ),
        ToolParam(
          key: 'tools',
          label: '允许的工具',
          type: ToolParamType.json,
          hint: '工具 id 数组，例如 ["page.click", "page.type"]。',
        ),
        ToolParam(
          key: 'maxSteps',
          label: '最多步数',
          type: ToolParamType.number,
          defaultValue: 6,
        ),
      ],
      outputSchema: {'summary': 'string', 'extractedData': 'object'},
    ),

    // ---------------------------------------------------------------- ui
    ToolDescriptor(
      id: 'ui.show',
      name: '展示结果',
      description: '把最终结果以 Markdown 卡片展示给用户。',
      risk: ToolRisk.read,
      availability: ToolAvailability.background,
      params: [
        ToolParam(
          key: 'title',
          label: '标题',
          type: ToolParamType.text,
          required: true,
        ),
        ToolParam(
          key: 'markdown',
          label: '内容',
          type: ToolParamType.multiline,
          required: true,
        ),
      ],
      outputSchema: {'shown': 'boolean'},
    ),

    // -------------------------------------------------------------- future
    ToolDescriptor(
      id: 'macro.run',
      name: '回放宏片段',
      description: '回放一段录制的固定动作。',
      risk: ToolRisk.write,
      idempotent: false,
      requiresConfirmation: true,
      params: [
        ToolParam(
          key: 'macroId',
          label: '宏 ID',
          type: ToolParamType.text,
          required: true,
        ),
        ToolParam(
          key: 'maxSteps',
          label: '最多步数',
          type: ToolParamType.number,
          defaultValue: 20,
        ),
      ],
      outputSchema: {'completed': 'boolean'},
    ),
    ToolDescriptor(
      id: 'notify',
      name: '系统通知',
      description: '发送一条本地通知。',
      risk: ToolRisk.read,
      availability: ToolAvailability.background,
      params: [
        ToolParam(
          key: 'title',
          label: '标题',
          type: ToolParamType.text,
          required: true,
        ),
        ToolParam(
          key: 'body',
          label: '内容',
          type: ToolParamType.multiline,
          required: true,
        ),
      ],
      outputSchema: {'notified': 'boolean'},
    ),
  ];

  static final Map<String, ToolDescriptor> byId = {
    for (final tool in all) tool.id: tool,
  };

  /// Tools that are safe to wire in P1. Kept separate so the catalog can grow
  /// without silently enabling unfinished tools.
  static const Set<String> p1Ids = {
    'page.open',
    'page.refresh',
    'page.back',
    'page.read',
    'page.read_region',
    'page.wait',
    'page.scroll',
    'page.click',
    'page.type',
    'page.press_key',
    'ai.generate',
    'ui.show',
  };

  static List<ToolDescriptor> get p1 =>
      all.where((tool) => p1Ids.contains(tool.id)).toList();

  static const Set<String> p15Ids = {
    'ai.extract',
    'page.select',
    'page.hover',
    'agent.task',
  };

  static List<ToolDescriptor> get p15 =>
      all.where((tool) => p15Ids.contains(tool.id)).toList();

  /// P2 tools that are implemented and can be selected manually.
  static const Set<String> p2Ids = {
    'macro.run',
    'notify',
  };

  static List<ToolDescriptor> get p2 =>
      all.where((tool) => p2Ids.contains(tool.id)).toList();

  /// Everything the editor and runtime can execute today.
  static final Set<String> availableIds = {
    ...p1Ids,
    ...p15Ids,
    ...p2Ids,
  };

  static List<ToolDescriptor> get available =>
      all.where((tool) => availableIds.contains(tool.id)).toList();

  /// Tools the AI author may compose. Future tools stay out until they are
  /// implemented, so the model cannot generate an unusable draft.
  static Set<String> get authoringIds => {...p1Ids, ...p15Ids};

  static ToolDescriptor? find(String id) => byId[id];

  static bool isP1(String id) => p1Ids.contains(id);

  /// Compact catalog for the AI authoring prompt.
  static List<Map<String, dynamic>> promptCatalog(
      {bool includeFuture = false}) {
    final tools = includeFuture
        ? all
        : all.where((tool) => authoringIds.contains(tool.id)).toList();
    return tools.map((tool) => tool.toPromptJson()).toList();
  }
}
