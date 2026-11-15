import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../config/app_tokens.dart';
import '../../models/agent_state.dart';
import '../../utils/url_utils.dart';

/// The single place where a sensitive agent action is authorized.
///
/// The status strip and the agent panel link here instead of offering their own
/// approve button, so the decision always shows the same three facts: what will
/// run, which site it runs on, and the exact text that will be sent.
class AgentConfirmationCard extends StatelessWidget {
  final AgentState state;

  /// The step is the user's to do: no button here lets the agent do it.
  bool get handoff => state.confirmationHandoff;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final VoidCallback? onAllowSite;

  /// Compact mode drops the payload block to one line. Used when the card sits
  /// inside the already-scrollable agent panel.
  final bool compact;

  const AgentConfirmationCard({
    super.key,
    required this.state,
    required this.onConfirm,
    required this.onCancel,
    this.onAllowSite,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final muted = onSurface.withValues(alpha: 0.62);
    final hairline = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final host = hostOf(state.targetUrl ?? '');
    final reason = state.confirmationReason?.trim() ?? '';
    final payload = state.confirmationPayload?.trim() ?? '';

    final meta = [
      if (reason.isNotEmpty) '风险：$reason',
      if (host.isNotEmpty) '站点：${compactHost(host)}',
    ].join(' · ');

    return Semantics(
      container: true,
      label: state.confirmationNavigation ? '前往新站点待授权' : '敏感操作待授权',
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 6),
        decoration: BoxDecoration(
          color: AppTheme.dangerOf(isDark).withValues(alpha: isDark ? 0.12 : 0.06),
          borderRadius: BorderRadius.circular(AppRadius.icon),
          border: Border.all(
            color: AppTheme.dangerOf(isDark).withValues(alpha: 0.34),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.shield_outlined,
                    size: 15, color: AppTheme.dangerOf(isDark)),
                const SizedBox(width: 6),
                Text(
                  state.confirmationNavigation ? '前往新站点，等待授权' : '敏感操作，等待授权',
                  style: TextStyle(
                    color: AppTheme.dangerOf(isDark),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            if (payload.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                state.confirmationNavigation ? '将要访问' : '将发送',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                  color: muted,
                ),
              ),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Text(
                  payload,
                  maxLines: compact ? 2 : 5,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: onSurface,
                  ),
                ),
              ),
            ],
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: muted),
              ),
            ],
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: onCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: muted,
                    side: BorderSide(color: hairline),
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    textStyle: const TextStyle(fontSize: 12),
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(handoff ? '跳过这一步' : '取消任务'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: onConfirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.accentOf(isDark),
                    foregroundColor: isDark ? Colors.black : Colors.white,
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(handoff ? '我自己做完了' : '授权继续'),
                ),
              ],
            ),
            // A handoff is not a site policy question: allowing the site would
            // still not let the agent pay or type a password. Neither is a
            // navigation: that allow list waives *write* confirmations, and
            // answering "may I go there" with it would answer a different
            // question.
            if (!handoff &&
                !state.confirmationNavigation &&
                onAllowSite != null &&
                host.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onAllowSite,
                  icon: const Icon(Icons.verified_user_outlined, size: 14),
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 210),
                    child: Text(
                      '本站始终允许（${compactHost(host)}）',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.accentOf(isDark),
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Modal shell around [AgentConfirmationCard], presented automatically when a
/// task pauses on a sensitive action.
///
/// The sheet is often raised while the composer still has focus, so it has to
/// survive the IME: it lifts above the keyboard and scrolls instead of letting
/// the approve button sit underneath it.
class AgentConfirmationSheet extends StatelessWidget {
  final AgentState state;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final VoidCallback? onAllowSite;

  const AgentConfirmationSheet({
    super.key,
    required this.state,
    required this.onConfirm,
    required this.onCancel,
    this.onAllowSite,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppTheme.darkCard : AppTheme.lightCard;
    final media = MediaQuery.of(context);
    final keyboardInset = media.viewInsets.bottom;
    final maxHeight =
        (media.size.height - keyboardInset - media.viewPadding.top - 24)
            .clamp(240.0, media.size.height)
            .toDouble();

    return AnimatedPadding(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: Container(
            constraints: BoxConstraints(maxHeight: maxHeight),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadius.sheet),
                bottom: Radius.circular(AppRadius.sheet),
              ),
              border: Border.all(
                color: AppInk.hairline(isDark),
                width: AppStroke.hairline,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppInk.hairline(isDark),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: SingleChildScrollView(
                    child: AgentConfirmationCard(
                      state: state,
                      onConfirm: onConfirm,
                      onCancel: onCancel,
                      onAllowSite: onAllowSite,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
