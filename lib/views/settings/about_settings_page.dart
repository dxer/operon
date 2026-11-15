import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/app_theme.dart';
import '../../config/app_tokens.dart';
import '../../services/app_version_service.dart';
import '../widgets/operon_mark.dart';
import 'control_diagnostics_page.dart';

class AboutSettingsPage extends StatelessWidget {
  const AboutSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppTheme.darkCard : AppTheme.lightCard;
    final hairline = AppInk.hairline(isDark);

    return Scaffold(
      appBar: AppBar(
        title: const Text('关于 Operon'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpace.page,
          AppSpace.x4,
          AppSpace.page,
          AppSpace.page + MediaQuery.of(context).viewPadding.bottom,
        ),
        children: [
          const SizedBox(height: AppSpace.x3),
          Center(
            child: Column(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppInk.accentTint(isDark),
                    borderRadius: BorderRadius.circular(AppRadius.icon),
                  ),
                  child: Center(
                    child: OperonMark(
                      size: 22,
                      color: AppTheme.primaryOf(isDark),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.x2 + 2),
                Text(
                  'Operon',
                  style: AppType.body.copyWith(
                    color: AppInk.primary(isDark),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpace.x1),
                Text(
                  AppVersionService.fullLabel,
                  style: AppType.caption.copyWith(
                    color: AppInk.tertiary(isDark),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.x6),
          Material(
            color: cardColor,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.icon),
              side: BorderSide(color: hairline, width: AppStroke.hairline),
            ),
            child: Column(
              children: [
                ListTile(
                  dense: true,
                  leading: Icon(
                    Icons.developer_mode_rounded,
                    size: 19,
                    color: AppTheme.warningOf(isDark),
                  ),
                  title: Text(
                    '控制层自检',
                    style: AppType.label.copyWith(
                      color: AppInk.primary(isDark),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    '检测页面读取、输入与截图链路',
                    style: AppType.caption.copyWith(
                      color: AppInk.tertiary(isDark),
                    ),
                  ),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppInk.tertiary(isDark),
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ControlDiagnosticsPage(),
                      ),
                    );
                  },
                ),
                Divider(
                  height: AppStroke.hairline,
                  thickness: AppStroke.hairline,
                  indent: 52,
                  color: hairline,
                ),
                ListTile(
                  dense: true,
                  leading: Icon(
                    Icons.code_rounded,
                    size: 19,
                    color: AppInk.secondary(isDark),
                  ),
                  title: Text(
                    '开源代码仓库',
                    style: AppType.label.copyWith(
                      color: AppInk.primary(isDark),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    'https://github.com/dxer/operon',
                    style: AppType.caption.copyWith(
                      color: AppInk.tertiary(isDark),
                    ),
                  ),
                  trailing: Icon(
                    Icons.copy_rounded,
                    size: 16,
                    color: AppInk.tertiary(isDark),
                  ),
                  onTap: () {
                    Clipboard.setData(
                      const ClipboardData(
                        text: 'https://github.com/dxer/operon',
                      ),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已复制仓库地址')),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
