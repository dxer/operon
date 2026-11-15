part of 'control.dart';

/// The value types a tool parameter can take, and the JSON Schema type for it.
enum ControlParamType { text, number, boolean, choice, objectList }

/// One tool parameter: the name the model must use, what it means, and whether
/// it is required.
class ControlParam {
  const ControlParam({
    required this.name,
    required this.description,
    this.type = ControlParamType.text,
    this.required = false,
    this.options = const [],
    this.itemFields = const [],
  });

  final String name;
  final String description;
  final ControlParamType type;
  final bool required;

  /// Allowed values for [ControlParamType.choice].
  final List<String> options;

  /// The shape of each entry for [ControlParamType.objectList].
  final List<ControlParam> itemFields;

  Map<String, Object?> toJsonSchema() => {
        'type': switch (type) {
          ControlParamType.text || ControlParamType.choice => 'string',
          ControlParamType.number => 'number',
          ControlParamType.boolean => 'boolean',
          ControlParamType.objectList => 'array',
        },
        'description': description,
        if (options.isNotEmpty) 'enum': options,
        if (type == ControlParamType.objectList && itemFields.isNotEmpty)
          'items': {
            'type': 'object',
            'properties': {
              for (final field in itemFields) field.name: field.toJsonSchema(),
            },
            if (itemFields.any((field) => field.required))
              'required': [
                for (final field in itemFields)
                  if (field.required) field.name,
              ],
            'additionalProperties': false,
          },
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
          'required': params
              .where((param) => param.required)
              .map((param) => param.name)
              .toList(),
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
    name: 'fill_form',
    summary: '一次填写多个输入框或原生下拉框，可选地点击提交。'
        '字段互不依赖时用它，比逐个 type/select 少很多往返；'
        '给出 submitRef 时，人工授权模式会先让用户看到全部字段与提交目标。',
    params: [
      ControlParam(
        name: 'fields',
        description: '要填的字段，按页面上的顺序排列',
        type: ControlParamType.objectList,
        required: true,
        itemFields: [
          ControlParam(
            name: 'ref',
            description: '输入框或下拉框的 ref',
            required: true,
          ),
          ControlParam(
            name: 'value',
            description: '要填入的内容；下拉框填选项文字或选项 value',
          ),
          ControlParam(
            name: 'action',
            description: 'type 输入文字；select 选择原生下拉项。'
                '省略时，combobox / listbox 按 select 处理，其余按 type 处理',
            type: ControlParamType.choice,
            options: ['type', 'select'],
          ),
          ControlParam(
            name: 'optionValue',
            description: '下拉项的 value，比选项文字更精确',
          ),
          ControlParam(
            name: 'optionIndex',
            description: '下拉项下标，从 0 开始',
            type: ControlParamType.number,
          ),
          ControlParam(
            name: 'replace',
            description: '输入前清空原内容，默认 true',
            type: ControlParamType.boolean,
          ),
          ControlParam(
            name: 'secret',
            description: '内容是密码或验证码：不记录正文，并且会交给用户自己完成',
            type: ControlParamType.boolean,
          ),
        ],
      ),
      ControlParam(
        name: 'submitRef',
        description: '提交按钮的 ref；省略表示只填写、不提交',
      ),
    ],
    mutates: true,
  ),
  ControlToolSpec(
    name: 'clear',
    summary: '清空一个输入框里的内容，不动别的地方。',
    params: [
      ControlParam(name: 'ref', description: '输入框的 ref', required: true),
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
      ControlParam(
        name: 'amount',
        description: '像素距离，默认约 0.8 屏',
        type: ControlParamType.number,
      ),
      ControlParam(name: 'ref', description: '要滚动的容器 ref；省略则滚页面'),
    ],
    mutates: true,
  ),
  ControlToolSpec(
    name: 'navigate',
    summary: '打开一个网址并等待加载完成。打开后必须重新 snapshot。',
    params: [
      ControlParam(name: 'url', description: '网址', required: true),
      ControlParam(
        name: 'newTab',
        description: '在新标签页打开，保留当前页，默认 false',
        type: ControlParamType.boolean,
      ),
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
    name: 'close_tab',
    summary: '关闭一个标签页。默认关当前这个；最后一个标签页不能关。',
    params: [
      ControlParam(
        name: 'tabId',
        description: 'tabs 返回的 id 或列表序号，默认当前标签页',
      ),
    ],
    mutates: true,
  ),
  ControlToolSpec(
    name: 'upload',
    summary: '把设备上的文件交给页面里的文件选择控件。省略 files 时会弹出系统文件选择器让用户选取。',
    params: [
      ControlParam(name: 'ref', description: '文件控件的 ref', required: true),
      ControlParam(
        name: 'files',
        description: '可选的文件绝对路径列表，用逗号分隔；通常省略并交给用户选择',
      ),
    ],
    mutates: true,
  ),
  ControlToolSpec(
    name: 'wait',
    summary: '等某个 ref 出现、等一段时间，或等页面稳定。',
    params: [
      ControlParam(name: 'ref', description: '等这个 ref 出现'),
      ControlParam(
        name: 'ms',
        description: '固定等待毫秒数，上限 10000',
        type: ControlParamType.number,
      ),
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
