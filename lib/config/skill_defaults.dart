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

  static List<Skill> all() => [
        ...instructionDefaults(),
        ...flowDefaults,
      ];

  static List<Skill> instructionDefaults() {
    return QuickCommandDefaults.all()
        .map((command) => SkillMigration.fromQuickCommand(
              command,
              origin: SkillOrigin.builtin,
            ))
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
        maxLlmCalls: 2,
        maxSideEffects: 0,
        maxItems: 1,
        maxDurationMs: 180000,
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
        maxLlmCalls: 0,
        maxSideEffects: 0,
        maxItems: 50,
        maxDurationMs: 60000,
      ),
      builtin: true,
      sortOrder: 6,
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
            'includeLinks': false,
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
        maxLlmCalls: 0,
        maxSideEffects: 0,
        maxItems: 1,
        maxDurationMs: 60000,
      ),
      builtin: true,
      sortOrder: 7,
    ),
  ];
}
