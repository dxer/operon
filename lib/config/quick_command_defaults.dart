import '../models/quick_command.dart';

/// Built-in examples. They are intentionally site-agnostic: the prompt talks
/// about "current list / feed / comment area" instead of X-specific selectors,
/// so users can reuse them on any similar page.
class QuickCommandDefaults {
  static List<QuickCommand> all() => [
        _smartReply(),
        _batchExtract(),
        _paginateExtract(),
        _batchForm(),
        _pageSummary(),
      ];

  // The id is kept as `quick_batch_reply` so existing installs upgrade the
  // skill in place instead of seeding a duplicate.
  static QuickCommand _smartReply() => const QuickCommand(
        id: 'quick_batch_reply',
        title: '智能回复',
        description: '阅读当前页面的一条条目并生成回复；只回复一条，不会连续处理',
        promptTemplate: '''
处理当前页面信息流、评论区或列表中的一条内容，只回复这一条，不要继续处理其他条目。

1. 先读取目标条目的正文、作者和上下文。如果是广告、抽奖、招聘或与主题无关的内容，停止并说明，不要继续寻找下一条。
2. 回复方式：{{replyMode}}。选择“AI 生成”时，根据该条目的具体内容生成回复；选择“固定文案”时，使用：{{replyText}}。如果固定文案为空，则改为根据内容生成。
3. 回复语气：{{tone}}。回复必须回应条目里的某个具体观点或细节，禁止使用“非常有价值的分享”“感谢分享”“学习了”这类通用套话。
4. 长度 20-80 字，语言与条目一致。
5. 点击回复或评论入口，输入内容，然后只点击真正的“发送 / 回复 / 发布 / 提交”按钮完成提交。严禁点击“保存草稿”“存草稿”“保存”等草稿按钮；保存草稿不算完成，也不能代替提交。
6. 提交后确认页面出现回复结果，再用 finish 结束。
7. 出现验证码、频率限制或错误提示时立即停止并报告。''',
        inputs: [
          QuickCommandInput(
            key: 'tone',
            label: '回复语气',
            type: QuickCommandInputType.select,
            defaultValue: '友好',
            options: ['友好', '专业', '幽默', '简短'],
            required: true,
          ),
          QuickCommandInput(
            key: 'replyMode',
            label: '回复方式',
            type: QuickCommandInputType.select,
            defaultValue: 'AI 生成',
            options: ['AI 生成', '固定文案'],
            required: true,
          ),
          QuickCommandInput(
            key: 'replyText',
            label: '固定文案（仅固定模式）',
            type: QuickCommandInputType.multiline,
            defaultValue: '',
          ),
        ],
        policy: QuickCommandPolicy(
          mode: QuickCommandMode.single,
          maxItems: 1,
          uniqueTarget: true,
          uniqueContent: true,
          confirmBeforeSideEffect: true,
          showPayloadInConfirmation: true,
          maxSteps: 18,
        ),
        builtin: true,
        sortOrder: 0,
      );

  static QuickCommand _batchExtract() => const QuickCommand(
        id: 'quick_batch_extract',
        title: '批量抓取列表',
        description: '抓取当前列表/信息流的结构化数据，自动去重并汇总',
        promptTemplate: '''
抓取当前页面列表中的最多 {{count}} 条内容。

提取字段：{{fields}}。
要求：
1. 只提取页面真实存在的内容，不要编造。
2. 相同条目不要重复提取，跨次提取时也要去重。
3. 使用 extract_data 暂存，最后用 finish 汇总为 extracted_data。

如果当前视口内容不足，可以滚动或翻页继续查找，但不要重复提取已有条目。''',
        inputs: [
          QuickCommandInput(
            key: 'count',
            label: '最多抓取条数',
            type: QuickCommandInputType.number,
            defaultValue: '20',
            required: true,
          ),
          QuickCommandInput(
            key: 'fields',
            label: '提取字段',
            type: QuickCommandInputType.text,
            defaultValue: '标题、作者、链接、摘要',
            required: true,
          ),
        ],
        policy: QuickCommandPolicy(
          mode: QuickCommandMode.batch,
          maxItems: 50,
          uniqueTarget: true,
          uniqueContent: false,
          maxSteps: 30,
          confirmBeforeSideEffect: false,
        ),
        builtin: true,
        sortOrder: 1,
      );

  static QuickCommand _paginateExtract() => const QuickCommand(
        id: 'quick_paginate_extract',
        title: '分页抓取并汇总',
        description: '自动翻页收集多页列表数据，跨页去重后统一汇总',
        promptTemplate: '''
从当前页开始，最多处理 {{pages}} 页列表数据。

每页提取字段：{{fields}}。
要求：
1. 每页抓取完后再翻到下一页，不要跳页或重复抓取同一页。
2. 跨页去重，相同条目只保留一次。
3. 使用 extract_data 暂存，最后用 finish 汇总为 extracted_data。

如果页面没有下一页或出现登录/验证码/频率限制，停止并说明已完成多少页。''',
        inputs: [
          QuickCommandInput(
            key: 'pages',
            label: '最多页数',
            type: QuickCommandInputType.number,
            defaultValue: '3',
            required: true,
          ),
          QuickCommandInput(
            key: 'fields',
            label: '提取字段',
            type: QuickCommandInputType.text,
            defaultValue: '标题、作者、链接、摘要',
            required: true,
          ),
        ],
        policy: QuickCommandPolicy(
          mode: QuickCommandMode.paginate,
          maxItems: 3,
          uniqueTarget: true,
          uniqueContent: false,
          maxSteps: 36,
          confirmBeforeSideEffect: false,
        ),
        builtin: true,
        sortOrder: 2,
      );

  static QuickCommand _batchForm() => const QuickCommand(
        id: 'quick_batch_form',
        title: '批量填写表单',
        description: '按行读取数据，逐条填写并提交重复表单',
        promptTemplate: '''
当前页面有重复表单或可批量填写的列表。按顺序处理最多 {{count}} 条。

数据如下（每行一条，字段用 | 分隔）：
{{data}}

列顺序：{{columns}}。
要求：
1. 每条数据只填写一次，不要重复提交。
2. 填写前确认字段对应正确；不确定时停止并说明。
3. 提交后确认成功提示或页面变化，再处理下一条。
4. 遇到验证码、频率限制或错误提示时立即停止。''',
        inputs: [
          QuickCommandInput(
            key: 'count',
            label: '处理条数',
            type: QuickCommandInputType.number,
            defaultValue: '3',
            required: true,
          ),
          QuickCommandInput(
            key: 'data',
            label: '数据（每行一条）',
            type: QuickCommandInputType.multiline,
            defaultValue: '',
            required: true,
          ),
          QuickCommandInput(
            key: 'columns',
            label: '列顺序',
            type: QuickCommandInputType.text,
            defaultValue: '姓名、电话、备注',
            required: true,
          ),
        ],
        policy: QuickCommandPolicy(
          mode: QuickCommandMode.batch,
          maxItems: 10,
          uniqueTarget: true,
          uniqueContent: false,
          pacingMs: 1500,
          confirmBeforeSideEffect: true,
          maxSteps: 30,
        ),
        builtin: true,
        sortOrder: 3,
      );

  static QuickCommand _pageSummary() => const QuickCommand(
        id: 'quick_page_summary',
        title: '页面内容总结',
        description: '提炼当前网页的核心观点、关键数据和结论',
        promptTemplate: '''
阅读当前网页正文，围绕以下重点进行总结：{{focus}}。

要求：
1. 只使用页面真实存在的信息，不要编造。
2. 输出 3-5 点关键摘要，每点一句话。
3. 最后给出一句简短结论。
4. 如果页面内容不足，直接说明，不要强行总结。''',
        inputs: [
          QuickCommandInput(
            key: 'focus',
            label: '总结重点',
            type: QuickCommandInputType.text,
            defaultValue: '核心观点、关键数据、结论',
            required: true,
          ),
        ],
        policy: QuickCommandPolicy(
          mode: QuickCommandMode.single,
          maxItems: 1,
          uniqueTarget: false,
          uniqueContent: false,
          maxSteps: 15,
          confirmBeforeSideEffect: false,
        ),
        builtin: true,
        sortOrder: 4,
      );
}
