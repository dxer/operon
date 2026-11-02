import '../models/tool_descriptor.dart';
import 'side_effect_ledger.dart';

/// Reason shown to the user before a write/destructive step.
class ConfirmationRequest {
  final String title;
  final String reason;
  final String target;
  final String? payload;
  final String? url;
  final ToolRisk risk;

  const ConfirmationRequest({
    required this.title,
    required this.reason,
    required this.target,
    this.payload,
    this.url,
    this.risk = ToolRisk.write,
  });
}

typedef ConfirmationHandler = Future<bool> Function(
  ConfirmationRequest request,
);

/// Shared runtime guard for skills. AgentRunner keeps its own orchestration for
/// now; the pure helpers here can be reused by both without a risky rewrite.
class ExecutionGuard {
  final bool safeMode;
  final ConfirmationHandler? onConfirm;
  final SideEffectLedger ledger = SideEffectLedger();

  final Set<String> _sentContents = {};
  final Set<String> _processedTargets = {};

  ExecutionGuard({
    this.safeMode = true,
    this.onConfirm,
  });

  bool contentAlreadySent(String text) {
    final normalized = normalizeContent(text);
    return normalized.isNotEmpty && _sentContents.contains(normalized);
  }

  void rememberContent(String text) {
    final normalized = normalizeContent(text);
    if (normalized.isNotEmpty) _sentContents.add(normalized);
  }

  bool targetAlreadyProcessed(String key) {
    final normalized = key.trim().toLowerCase();
    return normalized.isNotEmpty && _processedTargets.contains(normalized);
  }

  void rememberTarget(String key) {
    final normalized = key.trim().toLowerCase();
    if (normalized.isNotEmpty) _processedTargets.add(normalized);
  }

  Future<bool> confirm(ConfirmationRequest request) async {
    if (!safeMode && request.risk != ToolRisk.destructive) {
      return true;
    }
    final handler = onConfirm;
    if (handler == null) return false;
    return handler(request);
  }

  /// Never allow a secret value to reach logs, history or confirmation payloads.
  String maskSecrets(String text) {
    var masked = text;
    masked = masked.replaceAllMapped(
      RegExp(
        r'(password|passwd|token|api[_-]?key|cookie|密码|验证码|卡号|安全码)'
        r'\s*[:=]\s*\S+',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}: ••••••',
    );
    masked = masked.replaceAllMapped(
      RegExp(r'\bBearer\s+[A-Za-z0-9._-]{8,}', caseSensitive: false),
      (_) => 'Bearer ••••••',
    );
    return masked;
  }

  static String normalizeContent(String text) {
    return text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static bool looksRateLimited(String pageText) {
    final lower = pageText.toLowerCase();
    const patterns = [
      '操作过于频繁',
      '访问频繁',
      '请求过于频繁',
      '稍后再试',
      'rate limit',
      'too many requests',
      'try again later',
      'slow down',
    ];
    return patterns.any(lower.contains);
  }

  static bool looksCaptcha(String pageText) {
    final lower = pageText.toLowerCase();
    const patterns = [
      'captcha',
      '验证码',
      '人机验证',
      'verify you are human',
      'are you a robot',
      'cloudflare',
    ];
    return patterns.any(lower.contains);
  }
}
