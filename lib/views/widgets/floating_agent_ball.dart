import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/app_theme.dart';
import '../../models/agent_state.dart';

class FloatingAgentBall extends StatefulWidget {
  final AgentState state;
  final VoidCallback onTap;

  const FloatingAgentBall({
    Key? key,
    required this.state,
    required this.onTap,
  }) : super(key: key);

  @override
  State<FloatingAgentBall> createState() => _FloatingAgentBallState();
}

class _FloatingAgentBallState extends State<FloatingAgentBall>
    with TickerProviderStateMixin {
  // Ball Dimensions
  static const double ballSize = 54.0;
  static const double marginX = 8.0;

  // Position state
  Offset _position = Offset.zero;
  bool _isInitialized = false;
  bool _isDragging = false;
  bool _isDockedLeft = false;

  // Edge Snap Animation
  late AnimationController _snapAnimController;
  late Animation<Offset> _snapAnimation;

  // Pulse Animation for Running / Warning states
  late AnimationController _pulseAnimController;
  late Animation<double> _pulseAnimation;

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

    _pulseAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(
        parent: _pulseAnimController,
        curve: Curves.easeInOut,
      ),
    );

    _checkPulseState();
    _resetIdleTimer();
  }

  @override
  void didUpdateWidget(covariant FloatingAgentBall oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.status != oldWidget.state.status) {
      _checkPulseState();
      _wakeUp();
    }
  }

  void _checkPulseState() {
    if (widget.state.isRunning ||
        widget.state.status == AgentStatus.waitingConfirmation ||
        widget.state.status == AgentStatus.waitingCaptcha) {
      if (!_pulseAnimController.isAnimating) {
        _pulseAnimController.repeat(reverse: true);
      }
    } else {
      if (_pulseAnimController.isAnimating) {
        _pulseAnimController.stop();
        _pulseAnimController.value = 0;
      }
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
    _pulseAnimController.dispose();
    super.dispose();
  }

  void _snapToNearestEdge(Size screenSize) {
    final double midX = screenSize.width / 2;
    final double targetX = (_position.dx + ballSize / 2 < midX)
        ? marginX
        : (screenSize.width - ballSize - marginX);

    _isDockedLeft = targetX == marginX;

    // Vertical boundaries: preserve room for top address bar (~100) and bottom gestures (~80)
    final double minY = 90.0;
    final double maxY = screenSize.height - ballSize - 80.0;
    final double targetY = _position.dy.clamp(minY, maxY);

    final targetOffset = Offset(targetX, targetY);

    _snapAnimation = Tween<Offset>(
      begin: _position,
      end: targetOffset,
    ).animate(CurvedAnimation(
      parent: _snapAnimController,
      curve: Curves.easeOutBack,
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

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    // Initialize position near bottom-right on first frame
    if (!_isInitialized && screenSize.width > 0) {
      _position = Offset(
        screenSize.width - ballSize - marginX,
        screenSize.height - ballSize - 140,
      );
      _isInitialized = true;
    }

    final isRunning = widget.state.isRunning;
    final isWaiting = widget.state.status == AgentStatus.waitingConfirmation ||
        widget.state.status == AgentStatus.waitingCaptcha;

    Color glowColor = AppTheme.primary;
    if (isWaiting) {
      glowColor = AppTheme.warning;
    } else if (widget.state.status == AgentStatus.completed) {
      glowColor = AppTheme.accent;
    }

    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onPanStart: (_) {
          _wakeUp();
          setState(() {
            _isDragging = true;
          });
        },
        onPanUpdate: (details) {
          setState(() {
            _position += details.delta;
          });
        },
        onPanEnd: (_) {
          setState(() {
            _isDragging = false;
          });
          _snapToNearestEdge(screenSize);
        },
        onTap: () {
          _wakeUp();
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        child: AnimatedOpacity(
          opacity: _isDragging ? 1.0 : (_isDimmed ? 0.65 : 1.0),
          duration: const Duration(milliseconds: 250),
          child: ScaleTransition(
            scale: (isRunning || isWaiting) ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Glowing outer ring / shadow
                Container(
                  width: ballSize,
                  height: ballSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: glowColor.withOpacity(isRunning ? 0.55 : 0.35),
                        blurRadius: isRunning ? 16 : 10,
                        spreadRadius: isRunning ? 3 : 1,
                        offset: const Offset(0, 3),
                      ),
                    ],
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        glowColor,
                        glowColor.withOpacity(0.85),
                        const Color(0xFF0F141C),
                      ],
                    ),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.25),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: isRunning
                        ? const SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Icon(
                            isWaiting
                                ? Icons.warning_amber_rounded
                                : Icons.psychology_outlined,
                            color: Colors.white,
                            size: 28,
                          ),
                  ),
                ),

                // Running step counter badge or warning alert badge
                if (isRunning && widget.state.currentStep > 0)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.accent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white, width: 1.5),
                        boxShadow: const [
                          BoxShadow(color: Colors.black45, blurRadius: 4),
                        ],
                      ),
                      child: Text(
                        '#${widget.state.currentStep}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  )
                else if (isWaiting)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: AppTheme.warning,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: const Center(
                        child: Text(
                          '!',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
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
