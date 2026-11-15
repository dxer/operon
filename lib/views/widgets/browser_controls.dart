import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../config/app_tokens.dart';
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
    this.pageTitle,
    this.onReload,
    this.onStopLoad,
    this.onOpenAgent,
    this.agentBusy = false,
    this.isIncognito = false,
    this.onCopyUrl,
    this.onShareUrl,
    this.onFocusChanged,
  });

  final TextEditingController urlController;
  final bool isLoading;
  final double progress;
  final Function(String url) onSubmitUrl;
  final VoidCallback onSummarize;
  final String? pageTitle;
  final VoidCallback? onReload;
  final VoidCallback? onStopLoad;

  /// Opens the assistant. Null hides the entry.
  final VoidCallback? onOpenAgent;

  /// A task is running, so the entry says so instead of looking idle.
  final bool agentBusy;

  /// Marks the active tab as an incognito session.
  final bool isIncognito;

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
            color: AppInk.hairline(isDark),
            width: AppStroke.hairline,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.x1 + 2,
                AppSpace.x1 + 2,
                AppSpace.x3,
                AppSpace.x1 + 2,
              ),
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
                      pageTitle: widget.pageTitle,
                      isLoading: widget.isLoading,
                      isIncognito: widget.isIncognito,
                      onClear: _clear,
                      onSubmit: _submit,
                      onReload: widget.onReload,
                      onStopLoad: widget.onStopLoad,
                      onSummarize: widget.onSummarize,
                      contextMenuBuilder: _buildContextMenu,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: widget.isLoading && widget.progress < 1.0 ? 1.0 : 0.0,
              child: SizedBox(
                height: 2,
                child: widget.isLoading
                    ? LinearProgressIndicator(
                        value: widget.progress > 0.04 && widget.progress < 0.98
                            ? widget.progress
                            : null,
                        minHeight: 2,
                        backgroundColor: Colors.transparent,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppTheme.primaryOf(isDark),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
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
    required this.isLoading,
    this.isIncognito = false,
    required this.onClear,
    required this.onSubmit,
    required this.onSummarize,
    required this.contextMenuBuilder,
    this.pageTitle,
    this.onReload,
    this.onStopLoad,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isDark;
  final bool focused;
  final bool showClear;
  final bool isLoading;
  final bool isIncognito;
  final VoidCallback onClear;
  final VoidCallback onSubmit;
  final VoidCallback onSummarize;
  final Widget Function(BuildContext, EditableTextState) contextMenuBuilder;
  final String? pageTitle;
  final VoidCallback? onReload;
  final VoidCallback? onStopLoad;

  @override
  Widget build(BuildContext context) {
    final borderColor =
        focused ? AppTheme.primaryOf(isDark) : AppInk.hairline(isDark);
    final iconColor = AppInk.secondary(isDark);
    final url = controller.text;
    final secure = url.startsWith('https://');
    final hasRefreshControl = onReload != null || onStopLoad != null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      height: AppSpace.tap,
      decoration: BoxDecoration(
        color: AppInk.sunken(isDark),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(
          color: borderColor,
          width: focused ? 1.4 : AppStroke.hairline,
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: AppSpace.x3),
          Icon(
            isIncognito
                ? Icons.visibility_off_rounded
                : (secure
                    ? Icons.lock_rounded
                    : (url.isEmpty
                        ? Icons.search_rounded
                        : Icons.public_rounded)),
            size: 14,
            color: isIncognito
                ? AppTheme.primaryOf(isDark)
                : (secure ? AppTheme.accentOf(isDark) : iconColor),
          ),
          const SizedBox(width: AppSpace.x2),
          Expanded(child: _buildAddress()),
          // The clear button only shows while the user is typing: when
          // they are just reading a page it costs 44dp of address for a
          // control nobody needs yet.
          if (showClear)
            Semantics(
              button: true,
              label: '清空地址栏',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClear,
                child: SizedBox(
                  width: AppSpace.tap,
                  height: AppSpace.tap,
                  child: Center(
                    child: Icon(
                      Icons.cancel_rounded,
                      size: 15,
                      color: AppInk.tertiary(isDark),
                    ),
                  ),
                ),
              ),
            )
          else if (hasRefreshControl)
            _RefreshStopAction(
              isDark: isDark,
              isLoading: isLoading,
              onTap: isLoading ? onStopLoad : onReload,
            )
          else
            _SummarizeAction(isDark: isDark, onTap: onSummarize),
          const SizedBox(width: AppSpace.x1),
        ],
      ),
    );
  }

  /// The address, in two states.
  ///
  /// While reading, the address is information: the host carries the weight,
  /// because that is the part that answers "where am I", and the path sits back
  /// in grey. While typing, it has to be an ordinary text field again.
  ///
  /// The field stays mounted underneath at zero opacity in the reading state, so
  /// every keystroke, selection, controller listener and accessibility node
  /// keeps working exactly as before — and a tap anywhere on the address focuses
  /// it, the way tapping an address bar always has.
  Widget _buildAddress() {
    final editing = focused;
    final text = controller.text;

    return SizedBox(
      height: AppSpace.tap,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: editing ? 1 : 0,
              child: Center(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  style: AppType.body.copyWith(color: AppInk.primary(isDark)),
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
                    hintStyle:
                        AppType.body.copyWith(color: AppInk.tertiary(isDark)),
                  ),
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => onSubmit(),
                  onTapOutside: (_) => focusNode.unfocus(),
                  contextMenuBuilder: contextMenuBuilder,
                ),
              ),
            ),
          ),
          if (!editing)
            Positioned.fill(
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _buildReadingLabel(text),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReadingLabel(String urlText) {
    final cleanTitle = (pageTitle ?? '').trim();
    final hasPageTitle = cleanTitle.isNotEmpty &&
        cleanTitle != '新标签页' &&
        cleanTitle != '加载中...' &&
        urlText.isNotEmpty;
    if (hasPageTitle) {
      return Text(
        cleanTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppType.body.copyWith(
          color: AppInk.primary(isDark),
          fontWeight: FontWeight.w500,
        ),
      );
    }
    if (urlText.isEmpty) {
      return Text(
        '搜索或输入网址',
        style: AppType.body.copyWith(color: AppInk.tertiary(isDark)),
        maxLines: 1,
      );
    }
    return _AddressDisplay(text: urlText, isDark: isDark);
  }
}

/// Host at full strength, everything after it in grey.
class _AddressDisplay extends StatelessWidget {
  const _AddressDisplay({required this.text, required this.isDark});

  final String text;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final parts = _splitAuthority(text);
    final base = AppType.body.copyWith(
      color: AppInk.primary(isDark),
      fontWeight: FontWeight.w500,
    );
    final mute = AppType.body.copyWith(color: AppInk.tertiary(isDark));

    return Text.rich(
      TextSpan(
        style: mute,
        children: [
          if (parts.prefix.isNotEmpty) TextSpan(text: parts.prefix),
          TextSpan(text: parts.host, style: base),
          if (parts.rest.isNotEmpty) TextSpan(text: parts.rest),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Splits a URL into the part worth emphasising and the rest.
///
/// Deliberately string-based rather than `Uri.parse`: this draws on every
/// keystroke and has to survive half-typed input, which a parser rejects.
({String prefix, String host, String rest}) _splitAuthority(String url) {
  if (!url.contains('/') && !url.contains('.')) {
    // A search term, not an address. Nothing to emphasise.
    return (prefix: '', host: url, rest: '');
  }
  final schemeEnd = url.indexOf('://');
  final prefix = schemeEnd >= 0 ? url.substring(0, schemeEnd + 3) : '';
  final afterScheme = schemeEnd >= 0 ? url.substring(schemeEnd + 3) : url;
  final slash = afterScheme.indexOf('/');
  if (slash < 0) return (prefix: prefix, host: afterScheme, rest: '');
  return (
    prefix: prefix,
    host: afterScheme.substring(0, slash),
    rest: afterScheme.substring(slash),
  );
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
                    // A flat accent tint with the accent mark on it. The
                    // three-colour gradient that used to be here (green into
                    // blue into orange) read as decoration; a tinted square
                    // reads as a control, and it is the same tint the rest of
                    // the app uses for "selected".
                    Container(
                      decoration: BoxDecoration(
                        color: AppInk.accentTint(isDark),
                        borderRadius: BorderRadius.circular(AppRadius.icon),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.auto_awesome_rounded,
                          size: 16,
                          color: primary,
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

class _RefreshStopAction extends StatelessWidget {
  const _RefreshStopAction({
    required this.isDark,
    required this.isLoading,
    this.onTap,
  });

  final bool isDark;
  final bool isLoading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final label = isLoading ? '停止加载' : '刷新页面';
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: SizedBox(
          width: AppSpace.tap,
          height: AppSpace.tap,
          child: InkResponse(
            onTap: onTap == null
                ? null
                : () {
                    HapticService.selection();
                    onTap!();
                  },
            radius: 22,
            containedInkWell: true,
            highlightShape: BoxShape.circle,
            child: Center(
              child: Icon(
                isLoading ? Icons.close_rounded : Icons.refresh_rounded,
                size: 18,
                color: AppInk.secondary(isDark),
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
              // Two sparkles side by side (the AI entry and this) read as the
              // same button twice. Summarising a page is a reading action, so
              // it gets a document mark instead.
              child: Icon(
                Icons.subject_rounded,
                size: 17,
                color: AppInk.secondary(isDark),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
