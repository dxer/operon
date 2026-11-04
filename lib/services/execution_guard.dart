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

  /// Always ask, even with Safe Mode off. Used where the safety comes from the
  /// dialog itself rather than from the global setting, e.g. macro replay,
  /// which bypasses per-step risk checks.
  final bool required;

  const ConfirmationRequest({
    required this.title,
    required this.reason,
    required this.target,
    this.payload,
    this.url,
    this.risk = ToolRisk.write,
    this.required = false,
  });
}

typedef ConfirmationHandler = Future<bool> Function(
  ConfirmationRequest request,
);

enum ClickIntent { auto, navigate, toggle, submit, destructive }

/// Shared classification for a click target.
///
/// Both execution engines use this so "is this a write?" means the same thing
/// for instruction skills and flow skills.
class ClickAssessment {
  final bool sideEffect;
  final bool destructive;
  final bool draftBlocked;
  final String reason;

  const ClickAssessment({
    required this.sideEffect,
    required this.destructive,
    required this.draftBlocked,
    required this.reason,
  });
}

/// Shared runtime guard for skills. AgentRunner keeps its own orchestration for
/// now; the pure helpers here can be reused by both without a risky rewrite.
class ExecutionGuard {
  final bool safeMode;
  final ConfirmationHandler? onConfirm;
  final SideEffectLedger ledger = SideEffectLedger();

  /// When true (the default) a destructive action always asks, even with Safe
  /// Mode off. Skill authors can turn it off in the editor; the validator then
  /// warns that payments/deletes will no longer be confirmed.
  bool confirmDestructive;

  /// Human-wait hooks. Time spent in a confirmation dialog must not count
  /// against a skill's duration budget. Runners set these when they own one.
  void Function()? onWaitStart;
  void Function()? onWaitEnd;

  final Set<String> _sentContents = {};
  final Set<String> _processedTargets = {};

  ExecutionGuard({
    this.safeMode = true,
    this.onConfirm,
    this.confirmDestructive = true,
    this.onWaitStart,
    this.onWaitEnd,
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
    final forceDestructive = request.risk == ToolRisk.destructive &&
        (confirmDestructive || request.required);
    if (!safeMode && !forceDestructive) return true;
    final handler = onConfirm;
    if (handler == null) return false;
    onWaitStart?.call();
    try {
      return await handler(request);
    } finally {
      onWaitEnd?.call();
    }
  }

  void clearDedupe() {
    _sentContents.clear();
    _processedTargets.clear();
  }

  static final RegExp _submitPattern = RegExp(
    r'(回复|发布|发送|提交|评论|发推|支付|付款|购买|下单|确认|删除|注销|解绑|退出登录|关注|点赞|收藏|订阅|转发|保存)|'
    r'\b(reply|post|tweet|send|submit|publish|comment|confirm|delete|remove|unfollow|follow|like|favorite|subscribe|save)\b',
    caseSensitive: false,
  );

  static final RegExp _destructivePattern = RegExp(
    r'pay|payment|purchase|buy|checkout|place.?order|transfer|withdraw|refund|'
    r'delete|remove|unfollow|logout|'
    r'支付|付款|购买|下单|结算|转账|提现|退款|删除|注销|解绑|退出登录',
    caseSensitive: false,
  );

  /// Classifies a click target using the same rules for both engines.
  ///
  /// Generic, unclassified button clicks are deliberately not side effects;
  /// skill authors opt in with `intent: submit` / `intent: destructive`.
  static ClickAssessment assessClick({
    required String targetText,
    String thought = '',
    String description = '',
    bool componentSensitive = false,
    String sensitiveReason = '',
    String tag = '',
    String inputType = '',
    String declaredIntent = 'auto',
    bool expectNavigation = false,
  }) {
    if (looksLikeDraftAction(targetText)) {
      return const ClickAssessment(
        sideEffect: false,
        destructive: false,
        draftBlocked: true,
        reason: '草稿按钮',
      );
    }

    final intent = ClickIntent.values.firstWhere(
      (item) => item.name == declaredIntent,
      orElse: () => ClickIntent.auto,
    );
    switch (intent) {
      case ClickIntent.navigate:
      case ClickIntent.toggle:
        return ClickAssessment(
          sideEffect: false,
          destructive: false,
          draftBlocked: false,
          reason: '声明为 ${intent.name}',
        );
      case ClickIntent.submit:
        return const ClickAssessment(
          sideEffect: true,
          destructive: false,
          draftBlocked: false,
          reason: '声明为提交',
        );
      case ClickIntent.destructive:
        return const ClickAssessment(
          sideEffect: true,
          destructive: true,
          draftBlocked: false,
          reason: '声明为高危操作',
        );
      case ClickIntent.auto:
        break;
    }

    if (expectNavigation) {
      return const ClickAssessment(
        sideEffect: false,
        destructive: false,
        draftBlocked: false,
        reason: '预期跳转',
      );
    }

    final lowerTag = tag.toUpperCase();
    final lowerType = inputType.toLowerCase();
    const focusOnlyTypes = {
      '',
      'text',
      'password',
      'email',
      'search',
      'tel',
      'url',
      'number',
    };
    if (lowerTag == 'INPUT' && focusOnlyTypes.contains(lowerType)) {
      return const ClickAssessment(
        sideEffect: false,
        destructive: false,
        draftBlocked: false,
        reason: '聚焦输入框',
      );
    }

    final haystack = '$thought $targetText $description'.toLowerCase();
    if (isSearchOnly(haystack)) {
      return const ClickAssessment(
        sideEffect: false,
        destructive: false,
        draftBlocked: false,
        reason: '搜索操作',
      );
    }
    if (isComposerOpener(haystack, targetText)) {
      return const ClickAssessment(
        sideEffect: false,
        destructive: false,
        draftBlocked: false,
        reason: '打开回复/评论入口',
      );
    }

    final destructive = componentSensitive &&
        _destructivePattern.hasMatch(
          '${sensitiveReason.toLowerCase()} $haystack',
        );
    final sideEffect = destructive ||
        componentSensitive ||
        looksLikeSubmitIntent(
          thought: thought,
          targetText: targetText,
          description: description,
        );
    return ClickAssessment(
      sideEffect: sideEffect,
      destructive: destructive,
      draftBlocked: false,
      reason: sideEffect ? '提交/写入操作' : '普通点击',
    );
  }

  static bool looksLikeSubmitIntent({
    required String thought,
    required String targetText,
    required String description,
  }) {
    final haystack = '$thought $targetText $description';
    return _submitPattern.hasMatch(haystack);
  }

  /// A search/filter submission must not trigger publishing safeguards.
  static bool isSearchOnly(String haystack) {
    final lower = haystack.toLowerCase();
    final hasSearch = RegExp(r'搜索|搜一下|查找|筛选|search|filter').hasMatch(lower);
    if (!hasSearch) return false;
    final hasPublish = RegExp(
      r'回复|评论|发布|发帖|支付|付款|购买|下单|订单|转账|删除|注销|解绑|消息|'
      r'reply|comment|publish|pay|buy|order|delete|unfollow|logout',
    ).hasMatch(lower);
    return !hasPublish;
  }

  /// A click that only opens a reply/comment composer is not a submit.
  static bool isComposerOpener(String haystack, String targetText) {
    final lower = haystack.toLowerCase();
    final hasReply = RegExp(r'回复|评论|reply|comment').hasMatch(lower);
    final hasSend = RegExp(
      r'发送|发布|发帖|提交|send|post|publish|submit',
    ).hasMatch(lower);
    final exactTarget = targetText.trim().toLowerCase();
    if (hasReply) {
      if (RegExp(r'^(回复|评论|reply|comment)$').hasMatch(exactTarget)) {
        return true;
      }
      if (!hasSend) return true;
    }
    final navigates =
        RegExp(r'打开|查看|进入|浏览|open|view|go to|navigate').hasMatch(lower);
    final postTarget = RegExp(r'^(post|tweet|帖子|推文|动态)$').hasMatch(exactTarget);
    return navigates && postTarget && !hasSend;
  }

  static String normalizeContent(String text) {
    return text.toLowerCase().replaceAll(RegExp(r'[^\w一-龥]'), '');
  }

  /// True when a target is a draft-saving control rather than a real submit.
  ///
  /// Reply composers often put "保存草稿" next to the send button. Clicking it
  /// is an extra, non-publishing step and must never stand in for a reply.
  static bool looksLikeDraftAction(String targetText) {
    return RegExp(r'草稿|draft', caseSensitive: false).hasMatch(targetText);
  }

  static bool looksRateLimited(String pageText) {
    final lower = pageText.toLowerCase();
    const patterns = [
      '操作过于频繁',
      '操作频繁',
      '访问过于频繁',
      '访问频繁',
      '请求过于频繁',
      '稍后再试',
      'rate limit',
      'too many requests',
      'temporarily blocked',
      'unusual activity',
      'try again later',
      'slow down',
    ];
    return patterns.any(lower.contains);
  }
}
