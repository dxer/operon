import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/macro_workflow.dart';
import '../../services/storage_service.dart';
import '../../services/theme_service.dart';
import '../../services/app_version_service.dart';
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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _storage = await StorageService.getInstance();
    _themeService = await ThemeService.getInstance();
    await AppVersionService.load();
    if (mounted) {
      setState(() => _isLoading = false);
    }
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

  Widget _buildSettingTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
          width: 0.8,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: iconColor, size: 22),
        ),
        title: Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: Colors.grey,
          size: 22,
        ),
        onTap: () {
          onTap();
          if (mounted) {
            setState(() {});
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, 12 + MediaQuery.of(context).viewPadding.bottom),
        children: [
          _buildSettingTile(
            icon: Icons.tune_rounded,
            iconColor: const Color(0xFF1D9BF0),
            title: '通用与搜索',
            subtitle: '搜索引擎: $searchEngine · 主页与清除缓存',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const GeneralSettingsPage()),
            ),
          ),
          _buildSettingTile(
            icon: Icons.palette_outlined,
            iconColor: const Color(0xFF9333EA),
            title: '外观与个性化',
            subtitle: '主题: $themeStr · 字体缩放 ${_storage.getTextZoom()}%',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AppearanceSettingsPage()),
            ),
          ),
          _buildSettingTile(
            icon: Icons.security_rounded,
            iconColor: const Color(0xFF00BA7C),
            title: '浏览与隐私保护',
            subtitle:
                '${blockImages ? "无图模式" : "加载图片"} · ${jsEnabled ? "已启用 JS" : "禁用 JS"} · User-Agent',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BrowsingSettingsPage()),
            ),
          ),
          _buildSettingTile(
            icon: Icons.auto_awesome_rounded,
            iconColor: const Color(0xFFF59E0B),
            title: 'AI 智能体引擎',
            subtitle: llmConfig.model.isNotEmpty
                ? '${llmConfig.model} · 快速预设与连通测试'
                : '点击配置模型及 API 密钥',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AiEngineSettingsPage()),
            ),
          ),
          _buildSettingTile(
            icon: Icons.policy_rounded,
            iconColor: const Color(0xFFEF4444),
            title: 'AI 策略与自主权限',
            subtitle: '单次最大 $maxSteps 步 · ${safeMode ? "敏感操作拦截已开启" : "完全自主模式"}',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AiPolicySettingsPage(
                  onSafeModeChanged: widget.onSafeModeChanged,
                ),
              ),
            ),
          ),
          _buildSettingTile(
            icon: Icons.bolt_rounded,
            iconColor: Colors.amber,
            title: '技能',
            subtitle: 'AI 创建、工具编排、参数与执行策略',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SkillsPage(config: llmConfig)),
            ),
          ),
          _buildSettingTile(
            icon: Icons.history_rounded,
            iconColor: const Color(0xFF8B5CF6),
            title: '任务历史与审计',
            subtitle: _storage.getAgentTaskHistory().isEmpty
                ? '查看 AI 任务执行记录、授权与风险日志'
                : '最近 ${_storage.getAgentTaskHistory().length} 条任务记录',
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AgentHistoryPage()),
              );
              if (mounted) setState(() {});
            },
          ),
          _buildSettingTile(
            icon: Icons.extension_rounded,
            iconColor: const Color(0xFF06B6D4),
            title: '油猴脚本工坊 (UserScripts)',
            subtitle: '管理自定义 JavaScript 注入脚本与免登录插件',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const UserScriptsPage()),
            ),
          ),
          _buildSettingTile(
            icon: Icons.play_circle_outline_rounded,
            iconColor: const Color(0xFF6366F1),
            title: '自动化宏工作流',
            subtitle: '一键执行录制的复杂链式浏览器动作',
            onTap: () async => _openMacroDialog(),
          ),
          _buildSettingTile(
            icon: Icons.info_outline_rounded,
            iconColor: Colors.blueGrey,
            title: '关于 Operon',
            subtitle: '版本: ${AppVersionService.shortLabel} · 极简轻量 · 开源项目',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AboutSettingsPage()),
            ),
          ),
        ],
      ),
    );
  }
}
