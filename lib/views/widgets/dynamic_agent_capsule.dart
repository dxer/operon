import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/agent_state.dart';

class DynamicAgentCapsule extends StatefulWidget {
  final AgentState state;
  final VoidCallback onTap;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onStop;
  final VoidCallback? onQuickSummarize;
  final VoidCallback? onConfirmCaptcha;

  const DynamicAgentCapsule({
    Key? key,
    required this.state,
    required this.onTap,
    this.onPause,
    this.onResume,
    this.onStop,
    this.onQuickSummarize,
    this.onConfirmCaptcha,
  }) : super(key: key);

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

    // Determine Capsule Theme and Colors based on Agent Status
    Color capsuleBg = isDark ? const Color(0xF012161D) : const Color(0xF01E232B);
    Color borderColor = Colors.white.withOpacity(0.18);
    List<BoxShadow> shadows = [
      BoxShadow(
        color: Colors.black.withOpacity(0.38),
        blurRadius: 18,
        offset: const Offset(0, 6),
      ),
    ];

    Widget content;
    double targetWidth = 148.0;

    switch (state.status) {
      case AgentStatus.idle:
        targetWidth = 148.0;
        content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: _pulseAnimation,
              child: const Icon(
                Icons.auto_awesome,
                size: 16,
                color: Color(0xFF1D9BF0),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Operon AI',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
              ),
            ),
          ],
        );
        break;

      case AgentStatus.observing:
      case AgentStatus.thinking:
        targetWidth = 265.0;
        borderColor = const Color(0xFF1D9BF0).withOpacity(0.5);
        shadows.add(
          BoxShadow(
            color: const Color(0xFF1D9BF0).withOpacity(0.2),
            blurRadius: 14,
            spreadRadius: 1,
          ),
        );
        content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1D9BF0)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '正在分析网页 (${state.currentStep}/${state.maxSteps})',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 6),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: widget.onStop,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 14, color: Colors.white70),
              ),
            ),
          ],
        );
        break;

      case AgentStatus.executing:
        targetWidth = 300.0;
        borderColor = const Color(0xFF00BA7C).withOpacity(0.5);
        shadows.add(
          BoxShadow(
            color: const Color(0xFF00BA7C).withOpacity(0.2),
            blurRadius: 14,
            spreadRadius: 1,
          ),
        );
        content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: _pulseAnimation,
              child: const Icon(Icons.touch_app_rounded,
                  size: 16, color: Color(0xFF00BA7C)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _getActionSummary(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: widget.onPause,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.pause_rounded, size: 13, color: Colors.white),
                    SizedBox(width: 2),
                    Text(
                      '暂停',
                      style: TextStyle(
                          fontSize: 11,
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
        targetWidth = 275.0;
        borderColor = Colors.amber.withOpacity(0.7);
        shadows.add(
          BoxShadow(
            color: Colors.amber.withOpacity(0.25),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        );
        content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.pause_circle_outline_rounded, size: 16, color: Colors.amber),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                '已暂停 (触屏接管中)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: widget.onResume,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.play_arrow_rounded,
                        size: 14, color: Colors.amber),
                    SizedBox(width: 2),
                    Text(
                      '继续',
                      style: TextStyle(
                          fontSize: 11,
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
      case AgentStatus.waitingConfirmation:
        targetWidth = 265.0;
        borderColor = Colors.deepOrangeAccent.withOpacity(0.8);
        shadows.add(
          BoxShadow(
            color: Colors.deepOrangeAccent.withOpacity(0.3),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        );
        content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.verified_user_outlined,
                size: 16, color: Colors.deepOrangeAccent),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                '需完成安全验证',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: widget.onConfirmCaptcha ?? widget.onTap,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.deepOrangeAccent.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.deepOrangeAccent),
                ),
                child: const Text(
                  '完成',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        );
        break;

      case AgentStatus.completed:
        targetWidth = 230.0;
        borderColor = const Color(0xFF00BA7C).withOpacity(0.8);
        content = Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.check_circle_rounded,
                size: 16, color: Color(0xFF00BA7C)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '任务已达成 (点击查看)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
        break;

      case AgentStatus.error:
        targetWidth = 240.0;
        borderColor = Colors.redAccent.withOpacity(0.7);
        content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 16, color: Colors.redAccent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                state.errorMessage ?? '任务发生异常',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
        break;
    }

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        width: targetWidth,
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: capsuleBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: borderColor, width: 1.2),
          boxShadow: shadows,
        ),
        child: content,
      ),
    );
  }
}
