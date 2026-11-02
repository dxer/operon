import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import '../../models/agent_state.dart';

class DynamicAgentCapsule extends StatefulWidget {
  final AgentState state;
  final VoidCallback onTap;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onStop;
  final VoidCallback? onConfirmCaptcha;
  final VoidCallback? onConfirmAction;

  const DynamicAgentCapsule({
    super.key,
    required this.state,
    required this.onTap,
    this.onPause,
    this.onResume,
    this.onStop,
    this.onConfirmCaptcha,
    this.onConfirmAction,
  });

  @override
  State<DynamicAgentCapsule> createState() => _DynamicAgentCapsuleState();
}

class _DynamicAgentCapsuleState extends State<DynamicAgentCapsule>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _getActionSummary() {
    final act = widget.state.currentAction;
    if (act == null) return '正在执行操作...';

    switch (act.action.name) {
      case 'click':
        return act.thought.isNotEmpty ? act.thought : '正在点击目标元素...';
      case 'type':
        return act.thought.isNotEmpty ? act.thought : '正在填入文本...';
      case 'scroll':
        return act.direction == 'up' ? '向上滚动寻路' : '向下滚动寻路';
      case 'pressKey':
        return '按下键盘按键';
      case 'selectOption':
        return '选择下拉菜单';
      case 'goBack':
        return '返回上一页';
      case 'finish':
        return '任务达成总结';
      default:
        return act.thought.isNotEmpty ? act.thought : '处理中...';
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Lightweight Frosted Glass Capsule (Translucent + Soft Gaussian Blur)
    Color capsuleBg =
        isDark ? const Color(0xCC10151C) : const Color(0xDD1B222A);
    Color borderColor = Colors.white.withValues(alpha: 0.12);
    List<BoxShadow> shadows = [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.22),
        blurRadius: 10,
        offset: const Offset(0, 3),
      ),
    ];

    Widget content;
    double targetWidth = 96.0;
    double targetHeight = 32.0;

    switch (state.status) {
      case AgentStatus.idle:
        targetWidth = 104.0;
        targetHeight = 36.0;
        content = Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _pulseAnimation,
              child: const Icon(
                Icons.auto_awesome,
                size: 14,
                color: Color(0xFF1D9BF0),
              ),
            ),
            const SizedBox(width: 7),
            const Flexible(
              child: Text(
                'Operon',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        );
        break;

      case AgentStatus.observing:
      case AgentStatus.thinking:
        targetWidth = 210.0;
        targetHeight = 34.0;
        borderColor = const Color(0xFF1D9BF0).withValues(alpha: 0.45);
        shadows.add(
          BoxShadow(
            color: const Color(0xFF1D9BF0).withValues(alpha: 0.15),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        );
        content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1D9BF0)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '分析网页 (${state.currentStep}/${state.maxSteps})',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 4),
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: widget.onStop,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 12, color: Colors.white70),
              ),
            ),
          ],
        );
        break;

      case AgentStatus.executing:
        targetWidth = 240.0;
        targetHeight = 34.0;
        borderColor = const Color(0xFF00BA7C).withValues(alpha: 0.45);
        shadows.add(
          BoxShadow(
            color: const Color(0xFF00BA7C).withValues(alpha: 0.15),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        );
        content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: _pulseAnimation,
              child: const Icon(Icons.touch_app_rounded,
                  size: 14, color: Color(0xFF00BA7C)),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _getActionSummary(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 6),
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: widget.onPause,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.pause_rounded, size: 11, color: Colors.white),
                    SizedBox(width: 2),
                    Text(
                      '暂停',
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
        break;

      case AgentStatus.paused:
        targetWidth = 220.0;
        targetHeight = 34.0;
        borderColor = Colors.amber.withValues(alpha: 0.6);
        shadows.add(
          BoxShadow(
            color: Colors.amber.withValues(alpha: 0.2),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        );
        content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.pause_circle_outline_rounded,
                size: 14, color: Colors.amber),
            const SizedBox(width: 6),
            const Expanded(
              child: Text(
                '已暂停 (接管中)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 6),
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: widget.onResume,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber, width: 0.8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.play_arrow_rounded,
                        size: 12, color: Colors.amber),
                    SizedBox(width: 2),
                    Text(
                      '继续',
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.amber,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
        break;

      case AgentStatus.waitingCaptcha:
        targetWidth = 224.0;
        targetHeight = 34.0;
        borderColor = Colors.deepOrangeAccent.withValues(alpha: 0.7);
        shadows.add(
          BoxShadow(
            color: Colors.deepOrangeAccent.withValues(alpha: 0.25),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        );
        content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.verified_user_outlined,
                size: 14, color: Colors.deepOrangeAccent),
            const SizedBox(width: 6),
            const Expanded(
              child: Text(
                '需完成人机验证',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 6),
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: widget.onConfirmCaptcha ?? widget.onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.deepOrangeAccent.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: Colors.deepOrangeAccent, width: 0.8),
                ),
                child: const Text(
                  '已通过',
                  style: TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        );
        break;

      case AgentStatus.waitingConfirmation:
        targetWidth = 224.0;
        targetHeight = 34.0;
        borderColor = Colors.redAccent.withValues(alpha: 0.7);
        shadows.add(
          BoxShadow(
            color: Colors.redAccent.withValues(alpha: 0.25),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        );
        content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shield_outlined,
                size: 14, color: Colors.redAccent),
            const SizedBox(width: 6),
            const Expanded(
              child: Text(
                '敏感操作待授权',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 6),
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: widget.onConfirmAction ?? widget.onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.redAccent, width: 0.8),
                ),
                child: const Text(
                  '授权',
                  style: TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        );
        break;

      case AgentStatus.completed:
        targetWidth = 190.0;
        targetHeight = 34.0;
        borderColor = const Color(0xFF00BA7C).withValues(alpha: 0.7);
        content = const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded,
                size: 14, color: Color(0xFF00BA7C)),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                '任务已达成 (查看)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
        break;

      case AgentStatus.maxStepsReached:
        targetWidth = 190.0;
        targetHeight = 34.0;
        borderColor = Colors.amber.withValues(alpha: 0.7);
        content = const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_outlined, size: 14, color: Colors.amber),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                '已达步数上限 (查看)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
        break;

      case AgentStatus.error:
        targetWidth = 190.0;
        targetHeight = 34.0;
        borderColor = Colors.redAccent.withValues(alpha: 0.7);
        content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 14, color: Colors.redAccent),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                state.errorMessage ?? '任务发生异常',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
        break;
    }

    return Semantics(
      button: true,
      label: 'Operon AI 智能体',
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          width: targetWidth,
          height: targetHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(targetHeight / 2),
            border: Border.all(color: borderColor, width: 0.8),
            boxShadow: shadows,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(targetHeight / 2),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                color: capsuleBg,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
