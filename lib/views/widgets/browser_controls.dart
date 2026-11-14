import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../services/haptic_service.dart';

/// The address bar, with the assistant to the left of the pill.
///
/// The entry sits outside the pill on purpose: inside it competes with the
/// address for width, and on a phone the address is what the user is reading.
/// Outside it reads as "this is where the assistant lives", the way a browser
/// with a built-in assistant places it, and it stays in the same spot whether the
/// page is a blank tab or a form.
///
/// The input selects the whole URL the first time it gains focus so the user can
/// type a new address immediately.
class BrowserControls extends StatefulWidget {
  const BrowserControls({
    super.key,
    required this.urlController,
    required this.isLoading,
    required this.progress,
    required this.onSubmitUrl,
    required this.onSummarize,
    this.onOpenAgent,
    this.agentBusy = false,
    this.onCopyUrl,
    this.onShareUrl,
    this.onFocusChanged,
  });

  final TextEditingController urlController;
  final bool isLoading;
  final double progress;
  final Function(String url) onSubmitUrl;
  final VoidCallback onSummarize;

  /// Opens the assistant. Null hides the entry.
  final VoidCallback? onOpenAgent;

  /// A task is running, so the entry says so instead of looking idle.
  final bool agentBusy;

  /// Long-press actions on the address pill. `null` hides the entry.
  final VoidCallback? onCopyUrl;
  final VoidCallback? onShareUrl;

  /// The address field gained or lost focus. The page holds the chrome still
  /// while it is being typed into.
  final void Function(bool focused)? onFocusChanged;

  @override
  State<BrowserControls> createState() => _BrowserControlsState();
}

class _BrowserControlsState extends State<BrowserControls> {
  final FocusNode _focusNode = FocusNode();
  bool _showClear = false;
  bool _hasFocus = false;
  bool _selectedOnce = false;

  @override
  void initState() {
    super.initState();
    _showClear = widget.urlController.text.isNotEmpty;
    widget.urlController.addListener(_onUrlChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.urlController.removeListener(_onUrlChanged);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onUrlChanged() {
    final hasText = widget.urlController.text.isNotEmpty;
    if (_showClear != hasText) {
      setState(() => _showClear = hasText);
    }
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus && !_selectedOnce) {
      _selectedOnce = true;
      final text = widget.urlController.text;
      if (text.isNotEmpty) {
        widget.urlController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: text.length,
        );
      }
    } else if (!_focusNode.hasFocus) {
      _selectedOnce = false;
    }
    if (mounted && _hasFocus != _focusNode.hasFocus) {
      setState(() => _hasFocus = _focusNode.hasFocus);
      widget.onFocusChanged?.call(_focusNode.hasFocus);
    }
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    HapticService.selection();
    widget.onSubmitUrl(widget.urlController.text);
  }

  void _clear() {
    widget.urlController.clear();
    _focusNode.requestFocus();
  }

  /// Long-press menu for the address pill.
  ///
  /// A `GestureDetector` wrapped around the field would fight the text field's
  /// own long-press selection, so the copy/share entries are added to the
  /// selection toolbar instead. That keeps cut/paste available and gives the
  /// URL actions a predictable home.
  Widget _buildContextMenu(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    final items = <ContextMenuButtonItem>[
      ...editableTextState.contextMenuButtonItems,
      if (widget.onCopyUrl != null) ...[
        ContextMenuButtonItem(
          label: '复制链接',
          onPressed: () {
            editableTextState.hideToolbar();
            widget.onCopyUrl!();
          },
        ),
        ContextMenuButtonItem(
          label: '分享链接',
          onPressed: () {
            editableTextState.hideToolbar();
            widget.onShareUrl?.call();
          },
        ),
      ],
    ];
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: items,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final barBg = isDark ? AppTheme.darkBg : AppTheme.lightBg;

    return Container(
      decoration: BoxDecoration(
        color: barBg,
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.05),
            width: 0.6,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 7, 10, 7),
              child: Row(
                children: [
                  if (widget.onOpenAgent != null) ...[
                    AgentEntryButton(
                      isDark: isDark,
                      busy: widget.agentBusy,
                      onTap: widget.onOpenAgent!,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: _AddressPill(
                      controller: widget.urlController,
                      focusNode: _focusNode,
                      isDark: isDark,
                      focused: _hasFocus,
                      showClear: _showClear && _hasFocus,
                      onClear: _clear,
                      onSubmit: _submit,
                      onSummarize: widget.onSummarize,
                      contextMenuBuilder: _buildContextMenu,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: widget.isLoading ? 2 : 0,
              child: widget.isLoading
                  ? LinearProgressIndicator(
                      value: widget.progress > 0.03 && widget.progress < 0.97
                          ? widget.progress
                          : null,
                      minHeight: 2,
                      backgroundColor: Colors.transparent,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppTheme.primaryOf(isDark)),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// The rounded row that holds the lock, the address and its actions.
class _AddressPill extends StatelessWidget {
  const _AddressPill({
    required this.controller,
    required this.focusNode,
    required this.isDark,
    required this.focused,
    required this.showClear,
    required this.onClear,
    required this.onSubmit,
    required this.onSummarize,
    required this.contextMenuBuilder,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isDark;
  final bool focused;
  final bool showClear;
  final VoidCallback onClear;
  final VoidCallback onSubmit;
  final VoidCallback onSummarize;
  final Widget Function(BuildContext, EditableTextState) contextMenuBuilder;

  @override
  Widget build(BuildContext context) {
    final inputBg = isDark ? AppTheme.darkInput : AppTheme.lightInput;
    final borderColor = focused
        ? AppTheme.primaryOf(isDark)
        : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder);
    final iconColor = isDark ? AppTheme.darkMuted : AppTheme.lightMuted;
    final textColor = isDark ? AppTheme.darkOnSurface : AppTheme.lightOnSurface;
    final url = controller.text;
    final secure = url.startsWith('https://');

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      height: 46,
      decoration: BoxDecoration(
        color: inputBg,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: borderColor, width: 1.0),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Icon(
            secure
                ? Icons.lock_rounded
                : (url.isEmpty ? Icons.search_rounded : Icons.public_rounded),
            size: 15,
            color: secure ? AppTheme.accentOf(isDark) : iconColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: textColor,
              ),
              cursorColor: AppTheme.primaryOf(isDark),
              cursorRadius: const Radius.circular(2),
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: '搜索或输入网址',
                hintStyle: TextStyle(
                  fontSize: 13.5,
                  color: isDark ? Colors.white30 : Colors.black38,
                ),
              ),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => onSubmit(),
              onTapOutside: (_) => focusNode.unfocus(),
              contextMenuBuilder: contextMenuBuilder,
            ),
          ),
          // The clear button only shows while the user is typing: when they are
          // just reading a page it costs 44dp of address for a control nobody
          // needs yet.
          if (showClear)
            Semantics(
              button: true,
              label: '清空地址栏',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClear,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: Icon(
                      Icons.cancel_rounded,
                      size: 16,
                      color: isDark ? Colors.white30 : Colors.black26,
                    ),
                  ),
                ),
              ),
            ),
          _SummarizeAction(isDark: isDark, onTap: onSummarize),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

/// The assistant entry: a small bright mark to the left of the address.
///
/// Drawn rather than an icon font so it carries the app's own colours, and
/// tucked into a 44×44 touch target while staying visually 30×30 — the address
/// bar is a row of small things, and a full-size button would read as the most
/// important control on the screen.
class AgentEntryButton extends StatelessWidget {
  const AgentEntryButton({
    super.key,
    required this.isDark,
    required this.onTap,
    this.busy = false,
  });

  final bool isDark;
  final VoidCallback onTap;

  /// A task is running, so the mark is ringed instead of sitting still.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.primaryOf(isDark);
    final accent = AppTheme.accentOf(isDark);
    final warn = AppTheme.warningOf(isDark);
    return Semantics(
      button: true,
      label: busy ? 'AI 正在执行任务，打开面板' : '打开 AI 助手',
      child: Tooltip(
        message: busy ? 'AI 正在执行' : 'AI 助手',
        child: InkResponse(
          onTap: () {
            HapticService.selection();
            onTap();
          },
          radius: 22,
          containedInkWell: true,
          highlightShape: BoxShape.circle,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: SizedBox(
                width: 30,
                height: 30,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [accent, primary, warn.withValues(alpha: 0.9)],
                          stops: const [0.0, 0.55, 1.0],
                        ),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.auto_awesome_rounded,
                          size: 16,
                          color: Colors.white.withValues(alpha: 0.96),
                        ),
                      ),
                    ),
                    if (busy)
                      SizedBox(
                        width: 30,
                        height: 30,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.6,
                          valueColor: AlwaysStoppedAnimation<Color>(primary),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SummarizeAction extends StatelessWidget {
  const _SummarizeAction({required this.isDark, required this.onTap});

  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '速读此页',
      child: Tooltip(
        message: '速读此页',
        child: SizedBox(
          width: 44,
          height: 44,
          child: InkResponse(
            onTap: onTap,
            radius: 22,
            containedInkWell: true,
            highlightShape: BoxShape.circle,
            child: Center(
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppTheme.accentOf(isDark).withValues(alpha: isDark ? 0.16 : 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 15,
                  color: AppTheme.accentOf(isDark),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
