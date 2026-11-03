import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/agent_state.dart';

/// A calm, tactile floating control rather than a glowing "AI orb".
///
/// The puck stays neutral graphite so it reads as a browser tool on any page;
/// state is communicated by a thin ring and a small badge instead of a colored
/// gradient or a scaling pulse.
class FloatingAgentBall extends StatefulWidget {
  final AgentState state;
  final VoidCallback onTap;
  final VoidCallback? onQuickSummarize;

  const FloatingAgentBall({
    super.key,
    required this.state,
    required this.onTap,
    this.onQuickSummarize,
  });

  @override
  State<FloatingAgentBall> createState() => _FloatingAgentBallState();
}

class _FloatingAgentBallState extends State<FloatingAgentBall>
    with SingleTickerProviderStateMixin {
  // Keep a 52dp touch target while shrinking the visible puck.
  static const double ballSize = 52.0;
  static const double ringSize = 46.0;
  static const double puckSize = 40.0;
  static const double marginX = 8.0;

  static const Color _ink = Color(0xFF15171A);
  static const Color _inkTop = Color(0xFF343840);
  static const Color _bone = Color(0xFFF4F1EA);
  static const Color _warning = Color(0xFFC08A2E);
  static const Color _success = Color(0xFF2A8563);

  // Position state
  Offset _position = Offset.zero;
  bool _isInitialized = false;
  bool _isDragging = false;
  bool _isPressed = false;

  // Edge snap animation
  late AnimationController _snapAnimController;
  late Animation<Offset> _snapAnimation;

  // Inactivity auto-dim timer
  Timer? _idleTimer;
  bool _isDimmed = false;

  @override
  void initState() {
    super.initState();

    _snapAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    _resetIdleTimer();
  }

  @override
  void didUpdateWidget(covariant FloatingAgentBall oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.status != oldWidget.state.status) {
      _wakeUp();
    }
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    if (_isDimmed) {
      setState(() => _isDimmed = false);
    }
    _idleTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && !_isDragging && !widget.state.isRunning) {
        setState(() => _isDimmed = true);
      }
    });
  }

  void _wakeUp() {
    _resetIdleTimer();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _snapAnimController.dispose();
    super.dispose();
  }

  void _snapToNearestEdge(Size screenSize, double bottomInset) {
    final double midX = screenSize.width / 2;
    final double targetX = (_position.dx + ballSize / 2 < midX)
        ? marginX
        : (screenSize.width - ballSize - marginX);

    // Vertical boundaries: preserve room for the address bar and bottom toolbar.
    const double minY = 90.0;
    final double maxY = screenSize.height - ballSize - bottomInset;
    final double targetY = _position.dy.clamp(minY, maxY > minY ? maxY : minY);

    final targetOffset = Offset(targetX, targetY);

    _snapAnimation = Tween<Offset>(
      begin: _position,
      end: targetOffset,
    ).animate(CurvedAnimation(
      parent: _snapAnimController,
      curve: Curves.easeOutCubic,
    ))
      ..addListener(() {
        setState(() {
          _position = _snapAnimation.value;
        });
      });

    HapticFeedback.lightImpact();
    _snapAnimController.forward(from: 0.0);
    _resetIdleTimer();
  }

  Widget _buildStatusRing({
    required bool isWaiting,
    required bool isCompleted,
  }) {
    if (!isWaiting && !isCompleted) {
      return const SizedBox(width: ringSize, height: ringSize);
    }

    final color = isWaiting ? _warning : _success;
    return Container(
      width: ringSize,
      height: ringSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: color.withValues(alpha: 0.85),
          width: 1.8,
        ),
      ),
    );
  }

  /// Kept inside the puck so it stays visible on both light and dark pages.
  Widget _buildRunningSpinner() {
    return SizedBox(
      width: 35,
      height: 35,
      child: CircularProgressIndicator(
        strokeWidth: 1.8,
        strokeCap: StrokeCap.round,
        valueColor: AlwaysStoppedAnimation<Color>(
          _bone.withValues(alpha: 0.92),
        ),
        backgroundColor: _bone.withValues(alpha: 0.16),
      ),
    );
  }

  Widget _buildPuck({required bool isWaiting}) {
    return Container(
      width: puckSize,
      height: puckSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_inkTop, _ink],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.14),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
          if (isWaiting)
            BoxShadow(
              color: _warning.withValues(alpha: 0.28),
              blurRadius: 16,
              spreadRadius: 2,
            ),
        ],
      ),
      child: const Icon(
        Icons.touch_app_rounded,
        size: 18.5,
        color: _bone,
      ),
    );
  }

  Widget _buildStepBadge(int step) {
    return Positioned(
      top: -1,
      right: -1,
      child: Container(
        constraints: const BoxConstraints(minWidth: 16),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
        decoration: BoxDecoration(
          color: _bone,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _ink, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Text(
          '$step',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _ink,
            fontSize: 8.5,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ),
    );
  }

  Widget _buildAlertBadge() {
    return Positioned(
      top: -1,
      right: -1,
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: _warning,
          shape: BoxShape.circle,
          border: Border.all(color: _ink, width: 1.5),
        ),
        child: const Center(
          child: Text(
            '!',
            style: TextStyle(
              color: _ink,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDoneBadge() {
    return Positioned(
      top: -1,
      right: -1,
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: _success,
          shape: BoxShape.circle,
          border: Border.all(color: _ink, width: 1.5),
        ),
        child: const Icon(
          Icons.check_rounded,
          size: 10,
          color: _ink,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    // Keep the orb above the bottom toolbar and the system gesture area.
    final bottomInset = MediaQuery.of(context).padding.bottom + 72;

    // Initialize position near bottom-right on first frame
    if (!_isInitialized && screenSize.width > 0) {
      _position = Offset(
        screenSize.width - ballSize - marginX,
        screenSize.height - ballSize - bottomInset,
      );
      _isInitialized = true;
    }

    final isWaiting = widget.state.status == AgentStatus.waitingConfirmation ||
        widget.state.status == AgentStatus.waitingCaptcha;
    final isExecuting = widget.state.isRunning && !isWaiting;
    final isCompleted = widget.state.status == AgentStatus.completed;
    final step = widget.state.currentStep;

    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onPanStart: (_) {
          _wakeUp();
          setState(() {
            _isDragging = true;
            _isPressed = false;
          });
        },
        onPanUpdate: (details) {
          final maxY = screenSize.height - ballSize - bottomInset;
          setState(() {
            _position = Offset(
              (_position.dx + details.delta.dx)
                  .clamp(0.0, screenSize.width - ballSize),
              (_position.dy + details.delta.dy)
                  .clamp(90.0, maxY > 90.0 ? maxY : 90.0),
            );
          });
        },
        onPanEnd: (_) {
          setState(() {
            _isDragging = false;
          });
          _snapToNearestEdge(screenSize, bottomInset);
        },
        onTapDown: (_) {
          _wakeUp();
          setState(() => _isPressed = true);
        },
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: () {
          _wakeUp();
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        onLongPress: () {
          _wakeUp();
          setState(() => _isPressed = false);
          HapticFeedback.mediumImpact();
          if (widget.onQuickSummarize != null) {
            widget.onQuickSummarize!();
          } else {
            widget.onTap();
          }
        },
        child: Semantics(
          button: true,
          excludeSemantics: true,
          label: isWaiting
              ? 'AI 等待人工确认'
              : isExecuting
                  ? 'AI 正在执行，第 $step 步'
                  : isCompleted
                      ? 'AI 任务已完成'
                      : '打开 AI 操作面板',
          child: AnimatedOpacity(
            opacity: _isDragging ? 1.0 : (_isDimmed ? 0.55 : 1.0),
            duration: const Duration(milliseconds: 250),
            child: AnimatedScale(
              scale: _isPressed ? 0.94 : 1.0,
              duration: const Duration(milliseconds: 110),
              curve: Curves.easeOut,
              child: SizedBox(
                width: ballSize,
                height: ballSize,
                child: Center(
                  child: SizedBox(
                    width: ringSize,
                    height: ringSize,
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        _buildStatusRing(
                          isWaiting: isWaiting,
                          isCompleted: isCompleted,
                        ),
                        _buildPuck(isWaiting: isWaiting),
                        if (isExecuting) _buildRunningSpinner(),
                        if (isExecuting && step > 0)
                          _buildStepBadge(step)
                        else if (isWaiting)
                          _buildAlertBadge()
                        else if (isCompleted)
                          _buildDoneBadge(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
