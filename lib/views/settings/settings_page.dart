import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/macro_workflow.dart';
import '../../services/storage_service.dart';
import '../../services/theme_service.dart';
import '../../services/app_version_service.dart';
import '../../services/skill_service.dart';
import '../widgets/macro_dialog.dart';
import 'general_settings_page.dart';
import 'appearance_settings_page.dart';
import 'browsing_settings_page.dart';
import 'ai_engine_settings_page.dart';
import 'ai_policy_settings_page.dart';
import 'agent_history_page.dart';
import 'skills_page.dart';
import 'user_scripts_page.dart';
import 'about_settings_page.dart';

class SettingsPage extends StatefulWidget {
  /// Lets the browser execute a saved macro while the settings sheet is open.
  final Function(MacroWorkflow macro)? onRunMacro;

  /// Keeps a running agent in sync when the policy switch changes here.
  final ValueChanged<bool>? onSafeModeChanged;

  const SettingsPage({super.key, this.onRunMacro, this.onSafeModeChanged});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late StorageService _storage;
  late ThemeService _themeService;
  late SkillService _skillService;
  int _skillCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _storage = await StorageService.getInstance();
    _themeService = await ThemeService.getInstance();
    _skillService = await SkillService.getInstance();
    await AppVersionService.load();
    if (!mounted) return;
    setState(() {
      _skillCount = _skillService.getSkills().length;
      _isLoading = false;
    });
  }

  void _openMacroDialog() {
    showDialog(
      context: context,
      builder: (_) => MacroDialog(
        onRunMacro: (macro) {
          Navigator.of(context).pop();
          if (widget.onRunMacro != null) {
            widget.onRunMacro!(macro);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('已选择宏: ${macro.title}')),
            );
          }
        },
      ),
    );
  }

  Future<void> _openSkills() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SkillsPage(config: _storage.getLlmConfig()),
      ),
    );
    if (!mounted) return;
    setState(() => _skillCount = _skillService.getSkills().length);
  }

  Future<void> _openHistory() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AgentHistoryPage()),
    );
    if (!mounted) return;
    setState(() {});
  }

  Widget _buildSection(String title, List<Widget> rows) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppTheme.darkCard : AppTheme.lightCard;
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: onSurface.withValues(alpha: 0.52),
              ),
            ),
          ),
          Material(
            color: cardColor,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: borderColor, width: 0.8),
            ),
            child: Column(
              children: [
                for (var index = 0; index < rows.length; index++) ...[
                  if (index > 0)
                    Divider(
                      height: 0.8,
                      thickness: 0.8,
                      indent: 60,
                      color: borderColor,
                    ),
                  rows[index],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final muted = onSurface.withValues(alpha: isDark ? 0.68 : 0.58);

    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(12, 2, 10, 2),
      minVerticalPadding: 6,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 1),
        child: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11.5, height: 1.2, color: muted),
        ),
      ),
      trailing: trailing ??
          Icon(
            Icons.chevron_right_rounded,
            color: muted.withValues(alpha: 0.7),
            size: 20,
          ),
      onTap: () {
        onTap();
        if (mounted) setState(() {});
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final searchEngine = _storage.getSearchEngine().split(' ').first;
    final themeStr = _themeService.themeMode == ThemeMode.system
        ? '跟随系统'
        : (_themeService.themeMode == ThemeMode.light ? '浅色模式' : '暗色模式');
    final blockImages = _storage.getBlockImages();
    final jsEnabled = _storage.getJavaScriptEnabled();
    final llmConfig = _storage.getLlmConfig();
    final maxSteps = _storage.getMaxSteps();
    final safeMode = _storage.getSafeMode();
    final historyCount = _storage.getAgentTaskHistory().length;
    final modelName = llmConfig.model.split('/').last;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          16 + MediaQuery.of(context).viewPadding.bottom,
        ),
        children: [
          _buildSection('AI 与自动化', [
            _buildSettingRow(
              icon: Icons.auto_awesome_rounded,
              iconColor: AppTheme.primaryOf(isDark),
              title: 'AI 智能体引擎',
              subtitle:
                  modelName.isEmpty ? '配置模型与 API 密钥' : '$modelName · 快速预设与连通测试',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AiEngineSettingsPage(),
                ),
              ),
            ),
            _buildSettingRow(
              icon: Icons.policy_rounded,
              iconColor: AppTheme.accentOf(isDark),
              title: 'AI 策略与自主权限',
              subtitle: '单次 $maxSteps 步 · '
                  '${safeMode ? "人工授权已开启" : "完全自主模式"}',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AiPolicySettingsPage(
                    onSafeModeChanged: widget.onSafeModeChanged,
                  ),
                ),
              ),
            ),
            _buildSettingRow(
              icon: Icons.bolt_rounded,
              iconColor: AppTheme.primaryOf(isDark),
              title: '技能',
              subtitle: _skillCount == 0
                  ? 'AI 创建 · 工具编排 · 暂无技能'
                  : '$_skillCount 个技能 · AI 创建与工具编排',
              onTap: _openSkills,
            ),
            _buildSettingRow(
              icon: Icons.history_rounded,
              iconColor: AppTheme.neutralOf(isDark),
              title: '任务历史与审计',
              subtitle: historyCount == 0
                  ? '查看执行记录、授权与风险日志'
                  : '最近 $historyCount 条任务记录',
              onTap: _openHistory,
            ),
            _buildSettingRow(
              icon: Icons.play_circle_outline_rounded,
              iconColor: AppTheme.primaryOf(isDark),
              title: '快捷宏工作流',
              subtitle: '录制、管理与一键回放网页动作',
              trailing: Icon(
                Icons.play_circle_outline_rounded,
                size: 20,
                color: AppTheme.primaryOf(isDark),
              ),
              onTap: _openMacroDialog,
            ),
          ]),
          _buildSection('浏览与外观', [
            _buildSettingRow(
              icon: Icons.tune_rounded,
              iconColor: AppTheme.neutralOf(isDark),
              title: '通用与搜索',
              subtitle: '搜索引擎：$searchEngine · 主页与缓存',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const GeneralSettingsPage(),
                ),
              ),
            ),
            _buildSettingRow(
              icon: Icons.palette_outlined,
              iconColor: AppTheme.primaryOf(isDark),
              title: '外观与个性化',
              subtitle: '主题：$themeStr · 字号 ${_storage.getTextZoom()}%',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AppearanceSettingsPage(),
                ),
              ),
            ),
            _buildSettingRow(
              icon: Icons.security_rounded,
              iconColor: AppTheme.accentOf(isDark),
              title: '浏览与隐私保护',
              subtitle: '${blockImages ? "无图模式" : "加载图片"} · '
                  '${jsEnabled ? "JS 已启用" : "JS 已禁用"}',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const BrowsingSettingsPage(),
                ),
              ),
            ),
            _buildSettingRow(
              icon: Icons.extension_rounded,
              iconColor: AppTheme.neutralOf(isDark),
              title: '用户脚本',
              subtitle: '自定义注入脚本与免登录插件',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const UserScriptsPage()),
              ),
            ),
          ]),
          _buildSection('其他', [
            _buildSettingRow(
              icon: Icons.info_outline_rounded,
              iconColor: AppTheme.neutralOf(isDark),
              title: '关于 Operon',
              subtitle: '${AppVersionService.shortLabel} · 开源 · 极简轻量',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AboutSettingsPage()),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
