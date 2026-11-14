part of '../agent_bottom_sheet.dart';

// What scrolls: the run so far, and the cards that summarise it.

extension _SheetBody on _AgentBottomSheetState {
  Widget _buildScrollBody({
    required AgentState state,
    required bool isRunning,
    required bool hasExtractedData,
    required bool isDark,
    required Color cardBg,
    required Color onSurface,
    required Color muted,
    required Color subtle,
    required Color hairline,
    required Color surface,
    required Color warnInk,
  }) {
    return Flexible(
          child: SingleChildScrollView(
            controller: _scrollController,
            keyboardDismissBehavior:
                ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                _buildHeader(state: state, isRunning: isRunning),

                // A thin progress line gives an at-a-glance answer to
                // "how far along is this?" without another text row.
                if (isRunning && state.maxSteps > 0) ...[
                  const SizedBox(height: 8),
                  Semantics(
                    label: '任务进度 ${state.currentStep}/${state.maxSteps}',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: (state.currentStep / state.maxSteps)
                            .clamp(0.0, 1.0),
                        minHeight: 3,
                        backgroundColor: hairline,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppTheme.primaryOf(isDark),
                        ),
                      ),
                    ),
                  ),
                ],

                // Full-auto is a risky state, so keep a visible warning
                // instead of hiding it behind the compact chip.
                if (!_safeMode) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 14,
                        color: warnInk,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '全自动模式：支付、发布、删除等操作不会暂停确认',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: warnInk,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                // CAPTCHA Hand-Off Banner
                if (state.status == AgentStatus.waitingCaptcha) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
                    decoration: BoxDecoration(
                      color: warnInk.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: warnInk.withValues(alpha: 0.32),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.verified_user_outlined,
                              color: warnInk,
                              size: 15,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                state.captchaType == null
                                    ? '需要人机验证'
                                    : '需要人机验证 · ${state.captchaType}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: warnInk,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '请在上方网页完成验证，然后点击「我已完成验证」。',
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.4,
                            color: muted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            OutlinedButton(
                              onPressed: () =>
                                  widget.onConfirmCaptcha(false),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: muted,
                                side: BorderSide(color: hairline),
                                minimumSize: const Size(0, 44),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10),
                                textStyle:
                                    const TextStyle(fontSize: 11.5),
                                visualDensity: VisualDensity.compact,
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text('中止任务'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () =>
                                  widget.onConfirmCaptcha(true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.warning,
                                foregroundColor: Colors.black,
                                minimumSize: const Size(0, 44),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10),
                                textStyle: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                                visualDensity: VisualDensity.compact,
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text('我已完成验证'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],

                // Sensitive action. This is the same card that pops up
                // on its own when the panel is closed, and the only
                // surface that can approve a write.
                if (state.status == AgentStatus.waitingConfirmation) ...[
                  const SizedBox(height: 8),
                  AgentConfirmationCard(
                    state: state,
                    compact: true,
                    onConfirm: () => widget.onConfirmAction(true),
                    onCancel: () => widget.onConfirmAction(false),
                    onAllowSite: widget.onAllowSite,
                  ),
                ],

                // Result card: one place for the conclusion, step count and
                // follow-up actions instead of three stacked success banners.
                if (_hasResultCard(state)) ...[
                  const SizedBox(height: 8),
                  _buildResultCard(
                    state: state,
                    isDark: isDark,
                    surface: surface,
                    hairline: hairline,
                    onSurface: onSurface,
                    muted: muted,
                  ),
                ],

                // Extracted data: compact key/value preview, full view on demand.
                if (hasExtractedData) ...[
                  const SizedBox(height: 8),
                  _buildExtractedCard(
                    data: state.extractedData,
                    surface: surface,
                    hairline: hairline,
                    onSurface: onSurface,
                    muted: muted,
                  ),
                ],

                // Expandable Logs
                if (_showLogs) ...[
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 180),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: StepLogView(logs: state.logs),
                  ),
                ],
              ],
            ),
          ),
        );
  }
}
