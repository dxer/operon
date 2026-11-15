import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../widgets/operon_card.dart';
import '../../control/diagnostics.dart';

/// Runs the control layer's self-check on the page the user is looking at.
///
/// The layer talks to the WebView over the DevTools socket that Android starts
/// inside this app. That is the same mechanism a desktop debugger uses, so the
/// page has to be named here: this screen is where the user can see whether the
/// channel works on their device and their WebView build.
class ControlDiagnosticsPage extends StatefulWidget {
  const ControlDiagnosticsPage({super.key});

  @override
  State<ControlDiagnosticsPage> createState() => _ControlDiagnosticsPageState();
}

class _ControlDiagnosticsPageState extends State<ControlDiagnosticsPage> {
  static const ControlDiagnostics _diagnostics = ControlDiagnostics();
  List<DiagnosticCheck> _checks = const [];
  bool _running = false;
  String? _error;

  Future<void> _run({required bool tap}) async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final checks = <DiagnosticCheck>[];
      if (!tap) {
        checks.addAll(await _diagnostics.runSafe());
      } else {
        checks.add(await _diagnostics.probeInputTrust());
      }
      if (!mounted) return;
      setState(() => _checks = checks);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;

    return Scaffold(
      appBar: AppBar(title: const Text('控制层自检')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, 16 + MediaQuery.of(context).viewPadding.bottom),
        children: [
          Text(
            '控制层通过 Android WebView 自带的调试通道读取页面，并派发浏览器级的真实输入事件。'
            '下面的自检逐项验证这条链路在你这台设备上是否可用。',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: AppTheme.neutralOf(isDark),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _running ? null : () => _run(tap: false),
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: Text(_running ? '运行中…' : '运行自检（只读）'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _running ? null : () => _run(tap: true),
                  icon: const Icon(Icons.touch_app_rounded, size: 18),
                  label: const Text('测试真实输入'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '「测试真实输入」会在当前页面中间点一下，用来对比浏览器派发的事件与脚本合成的事件。'
            '页面中间若有可点元素会被触发，请在空白页或测试页上运行。',
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: AppTheme.warningOf(isDark),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _banner(_error!, AppTheme.dangerOf(isDark), isDark),
          ],
          if (_running) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ],
          if (_checks.isNotEmpty) ...[
            const SizedBox(height: 16),
            OperonCard(
              color: cardColor,
              borderColor: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
              radius: 16,
              child: Column(
                children: [
                  for (var index = 0; index < _checks.length; index++) ...[
                    if (index > 0) const Divider(height: 1),
                    _checkTile(_checks[index], isDark),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            '关于调试通道',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Operon 是一个自动化浏览器，控制网页是它的核心功能，因此 release 版本也保持 WebView 调试通道开启。'
            '该通道是本进程内的抽象 unix socket（@webview_devtools_remote_<pid>），只有同一应用的进程能连上，'
            '其它应用无法访问，也不会向网络开放任何端口。若你不需要控制层，可以在系统设置中限制本应用的后台活动。',
            style: TextStyle(
              fontSize: 11,
              height: 1.5,
              color: AppTheme.neutralOf(isDark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _checkTile(DiagnosticCheck check, bool isDark) {
    final color = check.ok ? AppTheme.accentOf(isDark) : AppTheme.dangerOf(isDark);
    return ListTile(
      dense: true,
      leading: Icon(
        check.ok ? Icons.check_circle_rounded : Icons.error_rounded,
        color: color,
        size: 20,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              check.name,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          if (check.ms != null)
            Text(
              '${check.ms}ms',
              style: TextStyle(fontSize: 11, color: AppTheme.neutralOf(isDark)),
            ),
        ],
      ),
      subtitle: Text(
        check.detail,
        style: TextStyle(fontSize: 11.5, height: 1.4, color: AppTheme.neutralOf(isDark)),
      ),
    );
  }

  Widget _banner(String text, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: TextStyle(fontSize: 12, color: color)),
    );
  }
}
