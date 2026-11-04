import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../services/haptic_service.dart';

/// Via-style compact address bar: one quiet row, a pill-shaped input, and a
/// single AI action. The input selects the whole URL the first time it gains
/// focus so the user can type a new address immediately.
class BrowserControls extends StatefulWidget {
  final TextEditingController urlController;
  final bool isLoading;
  final double progress;
  final Function(String url) onSubmitUrl;
  final VoidCallback onSummarize;

  /// Long-press actions on the address pill. `null` hides the entry.
  final VoidCallback? onCopyUrl;
  final VoidCallback? onShareUrl;

  const BrowserControls({
    super.key,
    required this.urlController,
    required this.isLoading,
    required this.progress,
    required this.onSubmitUrl,
    required this.onSummarize,
    this.onCopyUrl,
    this.onShareUrl,
  });

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
    }
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    HapticService.selection();
    widget.onSubmitUrl(widget.urlController.text);
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final barBg = isDark ? AppTheme.darkBg : AppTheme.lightBg;
    final inputBg = isDark ? AppTheme.darkInput : AppTheme.lightInput;
    final borderColor = isDark
        ? (_hasFocus ? AppTheme.primaryOf(isDark) : AppTheme.darkBorder)
        : (_hasFocus ? AppTheme.primaryOf(isDark) : AppTheme.lightBorder);
    final iconColor = isDark ? AppTheme.darkMuted : AppTheme.lightMuted;
    final textColor = isDark ? AppTheme.darkOnSurface : AppTheme.lightOnSurface;

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
              padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
              child: AnimatedContainer(
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
                      widget.urlController.text.startsWith('https://')
                          ? Icons.lock_rounded
                          : (widget.urlController.text.isEmpty
                              ? Icons.search_rounded
                              : Icons.public_rounded),
                      size: 15,
                      color: widget.urlController.text.startsWith('https://')
                          ? AppTheme.accentOf(isDark)
                          : iconColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: widget.urlController,
                        focusNode: _focusNode,
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
                        onSubmitted: (_) => _submit(),
                        onTapOutside: (_) => _focusNode.unfocus(),
                        contextMenuBuilder: _buildContextMenu,
                      ),
                    ),
                    if (_showClear)
                      Semantics(
                        button: true,
                        label: '清空地址栏',
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            widget.urlController.clear();
                            _focusNode.requestFocus();
                          },
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
                    _AiActionButton(
                      isDark: isDark,
                      onTap: () {
                        HapticService.selection();
                        widget.onSummarize();
                      },
                    ),
                    const SizedBox(width: 6),
                  ],
                ),
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
                      valueColor: AlwaysStoppedAnimation<Color>(
                          AppTheme.primaryOf(isDark)),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _AiActionButton extends StatelessWidget {
  final bool isDark;
  final VoidCallback onTap;

  const _AiActionButton({required this.isDark, required this.onTap});

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
                  color:
                      AppTheme.accentOf(isDark)
                          .withValues(alpha: isDark ? 0.16 : 0.12),
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
