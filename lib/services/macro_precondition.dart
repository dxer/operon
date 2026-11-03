import '../models/macro_workflow.dart';
import '../utils/url_utils.dart';

class MacroPreconditionResult {
  final bool ok;
  final String? reason;
  final bool legacyNoUrl;

  const MacroPreconditionResult({
    required this.ok,
    this.reason,
    this.legacyNoUrl = false,
  });
}

/// Replay is selector-based and does no per-step risk analysis, so it must at
/// least run on the host the macro was recorded on.
class MacroPrecondition {
  MacroPrecondition._();

  static MacroPreconditionResult check({
    required MacroWorkflow macro,
    required String currentUrl,
  }) {
    final currentHost = hostOf(currentUrl);
    if (currentHost.isEmpty ||
        currentUrl.startsWith('about:') ||
        currentUrl.startsWith('operon://')) {
      return const MacroPreconditionResult(
        ok: false,
        reason: '当前页面不是可执行的网页，请先打开目标网站',
      );
    }

    final expectedUrl = macro.initialUrl.trim();
    if (expectedUrl.isEmpty) {
      // Macros saved before initialUrl was recorded stay replayable.
      return const MacroPreconditionResult(ok: true, legacyNoUrl: true);
    }
    final expectedHost = hostOf(expectedUrl);
    if (expectedHost.isEmpty) {
      return const MacroPreconditionResult(
        ok: false,
        reason: '宏记录的目标网址无效，请重新录制后再运行',
      );
    }
    if (expectedHost != currentHost) {
      return MacroPreconditionResult(
        ok: false,
        reason: '这个宏是在 $expectedHost 上录制的，当前页面是 $currentHost，'
            '请先切换到对应网站',
      );
    }
    return const MacroPreconditionResult(ok: true);
  }
}
