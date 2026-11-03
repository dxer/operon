import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/app_constants.dart';
import '../../config/app_theme.dart';
import '../../services/app_version_service.dart';

class AboutSettingsPage extends StatelessWidget {
  const AboutSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;

    return Scaffold(
      appBar: AppBar(
        title: const Text('关于 Operon'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + MediaQuery.of(context).viewPadding.bottom),
        children: [
          const SizedBox(height: 16),
          Center(
            child: Column(
              children: [
                Text(
                  'OPERON',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 6.0,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  AppConstants.appSlogan,
                  style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.neutral,
                      letterSpacing: 1.0),
                ),
                const SizedBox(height: 16),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '版本: ${AppVersionService.fullLabel}',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                width: 0.8,
              ),
            ),
            child: Column(
              children: [
                const ListTile(
                  leading:
                      Icon(Icons.architecture_rounded, color: AppTheme.primary),
                  title: Text('轻量化设计',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: Text('参考 Via 浏览器的极简设计哲学与单手握持底栏交互，极低内存开销。',
                      style: TextStyle(fontSize: 12, color: AppTheme.neutral)),
                ),
                const Divider(height: 1),
                const ListTile(
                  leading:
                      Icon(Icons.psychology_rounded, color: AppTheme.accent),
                  title: Text('自主 Agent 引擎',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: Text('原生 DOM 语义感知、边缘吸附悬浮球与触屏即接管机制。',
                      style: TextStyle(fontSize: 12, color: AppTheme.neutral)),
                ),
                const Divider(height: 1),
                ListTile(
                  leading:
                      const Icon(Icons.code_rounded, color: AppTheme.neutral),
                  title: const Text('开源代码仓库',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: const Text('https://github.com/dxer/operon',
                      style: TextStyle(fontSize: 12, color: AppTheme.neutral)),
                  trailing: const Icon(Icons.copy_rounded, size: 18),
                  onTap: () {
                    Clipboard.setData(const ClipboardData(
                        text: 'https://github.com/dxer/operon'));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已复制项目仓库地址')),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Center(
            child: Text(
              'Operon Browser · 极简 · 智能 · 严谨',
              style: TextStyle(fontSize: 11, color: AppTheme.neutral),
            ),
          ),
        ],
      ),
    );
  }
}
