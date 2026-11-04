import '../models/skill.dart';
import '../services/skill_migration.dart';
import 'quick_command_defaults.dart';

/// Built-in skills.
///
/// The five instruction skills are the existing quick commands, preserved
/// verbatim. The three flow skills are small, read-only examples that exercise
/// the new step model without any write risk.
class SkillDefaults {
  SkillDefaults._();

  /// Shipped content revisions for built-in skills.
  ///
  /// `saveSkill` bumps a stored skill's `version`, so a stored version below
  /// the revision here means the user never edited it and it is safe to
  /// replace with the current shipped content.
  static const Map<String, int> builtinRevisions = {
    'quick_batch_reply': 2,
  };

  static Skill withRevision(Skill skill) {
    final revision = builtinRevisions[skill.id];
    return revision == null ? skill : skill.copyWith(version: revision);
  }

  static List<Skill> all() => [
        ...instructionDefaults(),
        ...flowDefaults.map(withRevision),
      ];

  static List<Skill> instructionDefaults() {
    return QuickCommandDefaults.all()
        .map((command) => withRevision(SkillMigration.fromQuickCommand(
              command,
              origin: SkillOrigin.builtin,
            )))
        .toList();
  }

  static const List<Skill> flowDefaults = [
    Skill(
      id: 'skill_region_summary',
      name: '区域内容总结',
      description: '读取当前页面的正文区域，按关注重点生成总结。',
      kind: SkillKind.flow,
      origin: SkillOrigin.builtin,
      inputs: [
        SkillInput(
          key: 'focus',
          label: '关注重点',
          defaultValue: '核心观点、关键数据、结论',
          required: true,
        ),
      ],
      steps: [
        SkillStep(
          id: 'read',
          name: '读取正文',
          tool: 'page.read_region',
          saveAs: 'content',
          params: {
            'locator': {
              'candidates': [
                {'type': 'css', 'value': 'article'},
                {'type': 'text', 'value': '正文', 'tag': 'article'},
                {'type': 'semantic', 'value': '页面正文区域'},
              ],
              'requireUnique': true,
            },
            'mode': 'text',
            'maxChars': 12000,
          },
          expect: StepExpectation(
            type: ExpectationType.dataNotEmpty,
          ),
        ),
        SkillStep(
          id: 'summary',
          name: 'AI 总结',
          tool: 'ai.generate',
          saveAs: 'summary',
          params: {
            'prompt': '围绕「{{inputs.focus}}」总结下面的网页内容。',
            'data': {
              'content': '{{steps.content.data}}',
            },
            'format': 'text',
          },
        ),
        SkillStep(
          id: 'show',
          name: '展示结果',
          tool: 'ui.show',
          params: {
            'title': '页面总结',
            'markdown': '{{steps.summary.data.text}}',
          },
        ),
      ],
      output: {
        'summary': '{{steps.summary.data.text}}',
      },
      policy: SkillPolicy(
        maxSteps: 8,
        maxSideEffects: 0,
        maxItems: 1,
        // Two model calls can each take up to the 3-minute request budget.
        maxDurationMs: 300000,
      ),
      builtin: true,
      sortOrder: 5,
    ),
    Skill(
      id: 'skill_link_collect',
      name: '链接批量收集',
      description: '读取当前页面主体里的链接，去重后汇总展示。',
      kind: SkillKind.flow,
      origin: SkillOrigin.builtin,
      inputs: [
        SkillInput(
          key: 'limit',
          label: '最多链接数',
          type: SkillInputType.number,
          defaultValue: '50',
          required: true,
        ),
      ],
      steps: [
        SkillStep(
          id: 'links',
          name: '收集链接',
          tool: 'page.read_region',
          saveAs: 'links',
          params: {
            'locator': {
              'candidates': [
                {'type': 'css', 'value': 'main'},
                {'type': 'css', 'value': 'body'},
                {'type': 'semantic', 'value': '页面主体内容'},
              ],
              'requireUnique': true,
            },
            'mode': 'items',
            'itemLocator': {
              'candidates': [
                {'type': 'css', 'value': 'a[href]'},
              ],
              'requireUnique': false,
            },
            'limit': '{{inputs.limit}}',
          },
        ),
        SkillStep(
          id: 'show',
          name: '展示链接',
          tool: 'ui.show',
          params: {
            'title': '页面链接',
            'markdown': '{{steps.links.data}}',
          },
        ),
      ],
      output: {
        'links': '{{steps.links.data.items}}',
      },
      policy: SkillPolicy(
        maxSteps: 6,
        maxSideEffects: 0,
        maxItems: 50,
        maxDurationMs: 60000,
      ),
      builtin: true,
      sortOrder: 6,
    ),
    Skill(
      id: 'skill_list_extract',
      name: '当前页列表抽取',
      description: '读取当前页面的重复条目，按字段抽取为结构化数据（只读）。',
      kind: SkillKind.flow,
      origin: SkillOrigin.builtin,
      inputs: [
        SkillInput(
          key: 'limit',
          label: '最多条数',
          type: SkillInputType.number,
          defaultValue: '20',
          required: true,
        ),
        SkillInput(
          key: 'schema',
          label: '字段结构',
          type: SkillInputType.multiline,
          defaultValue:
              '{"title":"标题","author":"作者","summary":"摘要","url":"链接"}',
          required: true,
        ),
        SkillInput(
          key: 'prompt',
          label: '抽取要求',
          type: SkillInputType.multiline,
          defaultValue: '按字段从每条内容中抽取；页面没有的字段留空，不要编造。',
          required: true,
        ),
      ],
      steps: [
        SkillStep(
          id: 'list',
          name: '读取列表条目',
          tool: 'page.read_region',
          saveAs: 'list',
          params: {
            'locator': {
              'candidates': [
                {'type': 'css', 'value': 'main'},
                {'type': 'css', 'value': 'body'},
                {'type': 'semantic', 'value': '页面主要内容区域'},
              ],
              'requireUnique': true,
            },
            'mode': 'items',
            'limit': '{{inputs.limit}}',
            'maxChars': 20000,
          },
          expect: StepExpectation(type: ExpectationType.dataNotEmpty),
        ),
        SkillStep(
          id: 'extract',
          name: '结构化抽取',
          tool: 'ai.extract',
          saveAs: 'extract',
          params: {
            'prompt': '{{inputs.prompt}}',
            'data': '{{steps.list.data}}',
            'schema': '{{inputs.schema}}',
          },
        ),
        SkillStep(
          id: 'show',
          name: '展示结果',
          tool: 'ui.show',
          params: {
            'title': '列表抽取结果',
            'markdown': '{{steps.extract.data.text}}',
          },
        ),
      ],
      output: {
        'extracted': '{{steps.extract.data.text}}',
      },
      policy: SkillPolicy(
        maxSteps: 6,
        maxSideEffects: 0,
        maxItems: 20,
        // Long enough for one slow extraction call plus the read step.
        maxDurationMs: 300000,
      ),
      builtin: true,
      sortOrder: 8,
    ),
    Skill(
      id: 'skill_page_export',
      name: '页面正文导出',
      description: '读取当前页面正文，原样展示，便于复制或继续处理。',
      kind: SkillKind.flow,
      origin: SkillOrigin.builtin,
      steps: [
        SkillStep(
          id: 'page',
          name: '读取页面',
          tool: 'page.read',
          saveAs: 'page',
          params: {
            'maxChars': 20000,
          },
          expect: StepExpectation(
            type: ExpectationType.dataNotEmpty,
          ),
        ),
        SkillStep(
          id: 'show',
          name: '展示正文',
          tool: 'ui.show',
          params: {
            'title': '页面正文',
            'markdown': '{{steps.page.data.content}}',
          },
        ),
      ],
      output: {
        'content': '{{steps.page.data.content}}',
      },
      policy: SkillPolicy(
        maxSteps: 4,
        maxSideEffects: 0,
        maxItems: 1,
        maxDurationMs: 60000,
      ),
      builtin: true,
      sortOrder: 7,
    ),
  ];
}
