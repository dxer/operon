import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../config/app_tokens.dart';
import '../../services/app_version_service.dart';
import '../widgets/operon_list_row.dart';
import 'about_settings_page.dart';
import 'agent_prompts_page.dart';
import 'ai_engine_settings_page.dart';
import 'ai_policy_settings_page.dart';
import 'appearance_settings_page.dart';
import 'browsing_settings_page.dart';
import 'general_settings_page.dart';

class SettingsPage extends StatefulWidget {
  /// Keeps a running agent in sync when the policy switch changes here.
  final ValueChanged<bool>? onSafeModeChanged;

  const SettingsPage({super.key, this.onSafeModeChanged});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    await AppVersionService.load();
    if (mounted) setState(() {});
  }

  Widget _buildSection(String title, List<Widget> rows) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppTheme.darkCard : AppTheme.lightCard;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.x3,
              0,
              AppSpace.x3,
              AppSpace.x1 + 2,
            ),
            child: Text(
              title,
              style: AppType.caption.copyWith(
                color: AppInk.tertiary(isDark),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Material(
            color: cardColor,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.icon),
              side: BorderSide(
                color: AppInk.hairline(isDark),
                width: AppStroke.hairline,
              ),
            ),
            child: Column(
              children: [
                for (var index = 0; index < rows.length; index++) ...[
                  if (index > 0)
                    Divider(
                      height: AppStroke.hairline,
                      thickness: AppStroke.hairline,
                      indent: 52,
                      color: AppInk.hairline(isDark),
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
    required Future<void> Function() onTap,
    Widget? trailing,
  }) {
    return OperonListRow(
      title: title,
      titleStyle: AppType.label.copyWith(fontWeight: FontWeight.w500),
      minHeight: AppSpace.tap + 2,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.x3 + 2),
      leadingSize: 28,
      leadingGap: AppSpace.x2 + 2,
      trailing: trailing,
      leading: _iconTile(icon: icon, color: iconColor),
      onTap: () => onTap(),
    );
  }

  Widget _iconTile({required IconData icon, required Color color}) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: color, size: 15),
    );
  }

  Future<void> _push(Widget page) {
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final versionLabel = AppVersionService.shortLabel;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpace.page,
          AppSpace.x2,
          AppSpace.page,
          AppSpace.page + MediaQuery.of(context).viewPadding.bottom,
        ),
        children: [
          _buildSection('AI 与自动化', [
            _buildSettingRow(
              icon: Icons.auto_awesome_rounded,
              iconColor: AppTheme.primaryOf(isDark),
              title: 'AI 智能体引擎',
              onTap: () => _push(const AiEngineSettingsPage()),
            ),
            _buildSettingRow(
              icon: Icons.policy_rounded,
              iconColor: AppTheme.accentOf(isDark),
              title: 'AI 策略与自主权限',
              onTap: () => _push(
                AiPolicySettingsPage(
                  onSafeModeChanged: widget.onSafeModeChanged,
                ),
              ),
            ),
            _buildSettingRow(
              icon: Icons.bolt_rounded,
              iconColor: AppTheme.primaryOf(isDark),
              title: '快捷指令',
              onTap: () => _push(const AgentPromptsPage()),
            ),
          ]),
          _buildSection('浏览与外观', [
            _buildSettingRow(
              icon: Icons.tune_rounded,
              iconColor: AppTheme.neutralOf(isDark),
              title: '通用与搜索',
              onTap: () => _push(const GeneralSettingsPage()),
            ),
            _buildSettingRow(
              icon: Icons.palette_outlined,
              iconColor: AppTheme.primaryOf(isDark),
              title: '外观与个性化',
              onTap: () => _push(const AppearanceSettingsPage()),
            ),
            _buildSettingRow(
              icon: Icons.security_rounded,
              iconColor: AppTheme.accentOf(isDark),
              title: '浏览与隐私保护',
              onTap: () => _push(const BrowsingSettingsPage()),
            ),
          ]),
          _buildSection('其他', [
            _buildSettingRow(
              icon: Icons.info_outline_rounded,
              iconColor: AppTheme.neutralOf(isDark),
              title: '关于 Operon',
              trailing: versionLabel.isEmpty
                  ? null
                  : Text(
                      versionLabel,
                      style: AppType.caption.copyWith(
                        color: AppInk.tertiary(isDark),
                      ),
                    ),
              onTap: () => _push(const AboutSettingsPage()),
            ),
          ]),
        ],
      ),
    );
  }
}
