import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/agent_action.dart';
import '../../models/agent_state.dart';

/// Docked agent status strip shown between the web page and the bottom toolbar.
/// Because it is part of the layout (not an overlay), it never covers page
/// content: the WebView simply gets 42px shorter while a task is active.
class AgentStatusBar extends StatelessWidget {
  final AgentState state;
  final VoidCallback onOpen;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;
  final VoidCallback onConfirmCaptcha;
  final VoidCallback onConfirmAction;
  final VoidCallback? onDismiss;
  final bool safeMode;

  const AgentStatusBar({
    super.key,
    required this.state,
    required this.onOpen,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onConfirmCaptcha,
    required this.onConfirmAction,
    this.onDismiss,
    this.safeMode = true,
  });

  bool get _isRunning =>
      state.status == AgentStatus.observing ||
      state.status == AgentStatus.thinking ||
      state.status == AgentStatus.executing;

  bool get _isPaused => state.status == AgentStatus.paused;

  bool get _isWaitingCaptcha => state.status == AgentStatus.waitingCaptcha;

  bool get _isWaitingConfirmation =>
      state.status == AgentStatus.waitingConfirmation;

  bool get _isFinished =>
      state.status == AgentStatus.completed ||
      state.status == AgentStatus.maxStepsReached ||
      state.status == AgentStatus.error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? AppTheme.darkBg : AppTheme.lightBg;
    final border = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.06);
    final onSurface = theme.colorScheme.onSurface;

    final meta = _metaFor(state);

    return Material(
      color: bg,
      child: InkWell(
        onTap: onOpen,
        child: Semantics(
          button: true,
          label: safeMode
              ? '${meta.title}，点击打开 AI 控制台'
              : '${meta.title}，完全自主模式，点击打开 AI 控制台',
          child: Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: border, width: 0.6)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 42,
                  child: Row(
                    children: [
                      const SizedBox(width: 14),
                      _StatusIcon(icon: meta.icon, color: meta.color),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          meta.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: onSurface,
                          ),
                        ),
                      ),
                      if (!safeMode && (_isRunning || _isPaused))
                        Tooltip(
                          message: '已关闭人工授权：AI 会自动执行敏感操作',
                          child: Container(
                            margin: const EdgeInsets.only(right: 4),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              '自主',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.redAccent,
                              ),
                            ),
                          ),
                        ),
                      ..._buildActions(meta.color),
                      const SizedBox(width: 6),
                    ],
                  ),
                ),
                if (_isRunning)
                  LinearProgressIndicator(
                    value: state.maxSteps > 0
                        ? (state.currentStep / state.maxSteps).clamp(0.0, 1.0)
                        : null,
                    minHeight: 2,
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(meta.color),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildActions(Color accent) {
    if (_isRunning) {
      return [
        _IconAction(icon: Icons.pause_rounded, tooltip: '暂停', onTap: onPause),
        _IconAction(icon: Icons.stop_rounded, tooltip: '停止', onTap: onStop),
      ];
    }
    if (_isPaused) {
      return [
        _IconAction(
          icon: Icons.play_arrow_rounded,
          tooltip: '继续',
          color: Colors.amber,
          onTap: onResume,
        ),
        _IconAction(icon: Icons.stop_rounded, tooltip: '停止', onTap: onStop),
      ];
    }
    if (_isWaitingCaptcha) {
      return [
        _TextAction(label: '已通过', color: accent, onTap: onConfirmCaptcha),
      ];
    }
    if (_isWaitingConfirmation) {
      return [
        _TextAction(label: '审阅', color: accent, onTap: onConfirmAction),
      ];
    }
    if (_isFinished) {
      return [
        _TextAction(label: '查看', color: accent, onTap: onOpen),
        if (onDismiss != null)
          _IconAction(
            icon: Icons.close_rounded,
            tooltip: '收起',
            onTap: onDismiss!,
          ),
      ];
    }
    return const [];
  }

  _StatusMeta _metaFor(AgentState state) {
    switch (state.status) {
      case AgentStatus.idle:
        return const _StatusMeta(
            'AI 待命', Icons.auto_awesome_rounded, AppTheme.primary);
      case AgentStatus.observing:
        return _StatusMeta(
          '正在读取页面 (${state.currentStep}/${state.maxSteps})',
          Icons.visibility_outlined,
          AppTheme.primary,
        );
      case AgentStatus.thinking:
        return _StatusMeta(
          'AI 正在规划下一步 (${state.currentStep}/${state.maxSteps})',
          Icons.psychology_outlined,
          const Color(0xFF9333EA),
        );
      case AgentStatus.executing:
        return _StatusMeta(
          _actionLabel(state.currentAction).isEmpty
              ? '正在操作网页'
              : _actionLabel(state.currentAction),
          Icons.touch_app_outlined,
          AppTheme.accent,
        );
      case AgentStatus.paused:
        return const _StatusMeta(
          '已暂停 · 触屏接管中',
          Icons.pause_circle_outline_rounded,
          Colors.amber,
        );
      case AgentStatus.waitingCaptcha:
        return _StatusMeta(
          '需完成人机验证 (${state.captchaType ?? "验证码"})',
          Icons.verified_user_outlined,
          Colors.deepOrangeAccent,
        );
      case AgentStatus.waitingConfirmation:
        final host = _hostOf(state.targetUrl);
        final reason =
            state.confirmationReason ?? _actionLabel(state.currentAction);
        return _StatusMeta(
          host.isEmpty ? '敏感操作待授权：$reason' : '敏感操作待授权：$reason · $host',
          Icons.shield_outlined,
          Colors.redAccent,
        );
      case AgentStatus.completed:
        return const _StatusMeta(
          '任务已完成 · 点击查看结果',
          Icons.check_circle_outline_rounded,
          AppTheme.accent,
        );
      case AgentStatus.maxStepsReached:
        return const _StatusMeta(
          '已达步数上限 · 任务未完成',
          Icons.timer_outlined,
          Colors.amber,
        );
      case AgentStatus.error:
        return _StatusMeta(
          state.errorMessage?.isNotEmpty == true
              ? '任务异常：${state.errorMessage}'
              : '任务发生异常 · 点击查看',
          Icons.error_outline_rounded,
          Colors.redAccent,
        );
    }
  }

  String _actionLabel(AgentAction? action) {
    if (action == null) return '';
    if (action.action == ActionType.type) {
      return '在 [${action.elementId}] 输入内容';
    }
    return action.description;
  }

  String _hostOf(String? url) {
    if (url == null || url.isEmpty) return '';
    var host = Uri.tryParse(url)?.host ?? '';
    host = host.toLowerCase();
    if (host.startsWith('www.')) host = host.substring(4);
    return host;
  }
}

class _StatusMeta {
  final String title;
  final IconData icon;
  final Color color;

  const _StatusMeta(this.title, this.icon, this.color);
}

class _StatusIcon extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _StatusIcon({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 14, color: color),
    );
  }
}

class _IconAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    return IconButton(
      icon: Icon(icon, size: 18),
      color: color ?? muted,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      onPressed: onTap,
    );
  }
}

class _TextAction extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _TextAction({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: color,
        minimumSize: const Size(0, 30),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
      ),
      child: Text(label),
    );
  }
}
