import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import '../../config/app_theme.dart';
import '../../config/app_tokens.dart';

/// Renders an answer as Markdown, in this app's type scale.
///
/// Parsing is the `markdown` package's job; drawing is ours. A ready-made
/// Markdown *widget* would bring its own font sizes, its own code-block
/// background and its own idea of a heading, which is exactly what the design
/// tokens exist to stop.
///
/// What it deliberately does not do:
/// * no images — an answer's `![](…)` is a remote fetch and a layout surprise,
///   so the alt text stands in;
/// * no raw HTML — the model writes prose, and a browser is not the place to
///   start interpreting markup it was handed;
/// * no user text — only the agent's own answers go through here. What the
///   user typed is shown as typed.
class MarkdownAnswer extends StatefulWidget {
  const MarkdownAnswer(
    this.text, {
    super.key,
    this.onOpenLink,
    this.baseStyle,
  });

  final String text;

  /// Tapping a link goes here. In a browser a link in an answer is a place to
  /// go, not decoration, so the default is to make it tappable.
  final ValueChanged<String>? onOpenLink;

  final TextStyle? baseStyle;

  @override
  State<MarkdownAnswer> createState() => _MarkdownAnswerState();
}

class _MarkdownAnswerState extends State<MarkdownAnswer> {
  late List<md.Node> _nodes;

  /// Tap recognizers must outlive the spans that use them and be disposed.
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void initState() {
    super.initState();
    _nodes = _parse(widget.text);
  }

  @override
  void didUpdateWidget(covariant MarkdownAnswer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _disposeRecognizers();
      _nodes = _parse(widget.text);
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  /// `Element.children` is nullable: a leaf has none.
  static List<md.Node> _kids(md.Element element) =>
      element.children ?? const <md.Node>[];

  List<md.Node> _parse(String source) {
    final text = source.trim();
    if (text.isEmpty) return const [];
    // GitHub flavoured for tables and strikethrough: models write in it.
    return md.Document(extensionSet: md.ExtensionSet.gitHubFlavored)
        .parseLines(text.split('\n'));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final style = widget.baseStyle ?? AppType.body;
    final blocks = <Widget>[];
    for (final node in _nodes) {
      final block = _buildBlock(node, isDark, style);
      if (block != null) {
        if (blocks.isNotEmpty) blocks.add(const SizedBox(height: AppSpace.x2));
        blocks.add(block);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: blocks,
    );
  }

  Widget? _buildBlock(md.Node node, bool isDark, TextStyle body) {
    final ink = AppInk.primary(isDark);
    if (node is md.Text) {
      return Text(node.text, style: body.copyWith(color: ink));
    }
    if (node is! md.Element) return null;

    switch (node.tag) {
      case 'p':
        return Text.rich(
          TextSpan(children: _inline(_kids(node), isDark, body, ink)),
          style: body.copyWith(color: ink),
        );
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        final style = switch (node.tag) {
          'h1' => AppType.title,
          'h2' => AppType.headline,
          _ => body.copyWith(fontWeight: FontWeight.w600),
        };
        return Padding(
          padding: EdgeInsets.only(top: node.tag == 'h1' ? 0 : AppSpace.x1),
          child: Text.rich(
            TextSpan(children: _inline(_kids(node), isDark, style, ink)),
            style: style.copyWith(color: ink),
          ),
        );
      case 'pre':
        return _buildCodeBlock(node, isDark);
      case 'blockquote':
        return Container(
          padding: const EdgeInsets.only(left: AppSpace.x3),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: AppInk.hairline(isDark), width: 2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final child in _kids(node))
                if (_buildBlock(child, isDark, body) case final widget?)
                  widget,
            ],
          ),
        );
      case 'ul':
      case 'ol':
        return _buildList(node, isDark, body);
      case 'hr':
        return Divider(height: AppSpace.x4, thickness: 1, color: AppInk.hairline(isDark));
      case 'table':
        return _buildTable(node, isDark, body);
      default:
        // Unknown block: render its children rather than dropping the text.
        final children = <Widget>[];
        for (final child in _kids(node)) {
          final widget = _buildBlock(child, isDark, body);
          if (widget != null) {
            if (children.isNotEmpty) {
              children.add(const SizedBox(height: AppSpace.x2));
            }
            children.add(widget);
          }
        }
        if (children.isEmpty) return null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        );
    }
  }

  Widget _buildList(md.Element node, bool isDark, TextStyle body) {
    final ordered = node.tag == 'ol';
    final start = int.tryParse(node.attributes['start'] ?? '') ?? 1;
    var index = 0;
    final rows = <Widget>[];
    for (final item in _kids(node).whereType<md.Element>()) {
      if (item.tag != 'li') continue;
      index++;
      final marker = ordered ? '${start + index - 1}.' : '•';
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.x1),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: ordered ? 22 : 14,
                child: Text(
                  marker,
                  style: body.copyWith(color: AppInk.tertiary(isDark)),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // A list item holds inline content, but a loose list can
                    // hold paragraphs, so both are handled.
                    for (final child in _kids(item))
                      if (child is md.Text)
                        Text.rich(
                          TextSpan(
                            children: _inline([child], isDark, body, AppInk.primary(isDark)),
                          ),
                          style: body.copyWith(color: AppInk.primary(isDark)),
                        )
                      else if (child is md.Element && child.tag != 'ul' && child.tag != 'ol')
                        _buildInlineElement(child, isDark, body)
                      else if (child is md.Element)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpace.x1),
                          child: _buildList(child, isDark, body),
                        ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }

  Widget _buildInlineElement(md.Element node, bool isDark, TextStyle body) {
    return Text.rich(
      TextSpan(children: _inline(_kids(node), isDark, body, AppInk.primary(isDark))),
      style: body.copyWith(color: AppInk.primary(isDark)),
    );
  }

  Widget _buildCodeBlock(md.Element node, bool isDark) {
    final code = _kids(node).whereType<md.Element>().firstOrNull;
    final text = code == null
        ? node.textContent
        : _kids(code).whereType<md.Text>().map((t) => t.text).join();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.x3),
      decoration: BoxDecoration(
        color: AppInk.sunken(isDark),
        borderRadius: BorderRadius.circular(AppRadius.icon),
        border: Border.all(color: AppInk.hairline(isDark)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(
          text.trimRight(),
          style: AppType.caption.copyWith(
            height: 1.5,
            color: AppInk.primary(isDark),
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }

  Widget _buildTable(md.Element node, bool isDark, TextStyle body) {
    final rows = <List<String>>[];
    var header = false;
    for (final section in _kids(node).whereType<md.Element>()) {
      if (section.tag == 'thead') header = true;
      for (final row in _kids(section).whereType<md.Element>()) {
        if (row.tag != 'tr') continue;
        rows.add([
          for (final cell in _kids(row).whereType<md.Element>())
            cell.textContent.trim(),
        ]);
      }
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppInk.hairline(isDark)),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var r = 0; r < rows.length; r++)
            Container(
              decoration: BoxDecoration(
                border: r == 0
                    ? null
                    : Border(top: BorderSide(color: AppInk.hairline(isDark))),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.x2,
                vertical: AppSpace.x1 + 2,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var c = 0; c < rows[r].length; c++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: AppSpace.x2),
                        child: Text(
                          rows[r][c],
                          style: (header && r == 0
                                  ? AppType.caption.copyWith(
                                      fontWeight: FontWeight.w600,
                                    )
                                  : AppType.caption)
                              .copyWith(
                            color: header && r == 0
                                ? AppInk.primary(isDark)
                                : AppInk.secondary(isDark),
                            height: 1.45,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<InlineSpan> _inline(
    List<md.Node> nodes,
    bool isDark,
    TextStyle style,
    Color ink,
  ) {
    final spans = <InlineSpan>[];
    for (final node in nodes) {
      if (node is md.Text) {
        spans.add(TextSpan(text: node.text, style: style.copyWith(color: ink)));
        continue;
      }
      if (node is! md.Element) continue;
      switch (node.tag) {
        case 'strong':
          spans.addAll(_inline(
            _kids(node),
            isDark,
            style.copyWith(fontWeight: FontWeight.w600),
            ink,
          ));
        case 'em':
          spans.addAll(_inline(
            _kids(node),
            isDark,
            style.copyWith(fontStyle: FontStyle.italic),
            ink,
          ));
        case 'del':
          spans.addAll(_inline(
            _kids(node),
            isDark,
            style.copyWith(decoration: TextDecoration.lineThrough),
            ink,
          ));
        case 'code':
          spans.add(TextSpan(
            text: node.textContent,
            style: AppType.caption.copyWith(
              color: ink,
              fontFamily: 'monospace',
              backgroundColor: AppInk.sunken(isDark),
            ),
          ));
        case 'a':
          final href = node.attributes['href'] ?? '';
          final label = _inline(_kids(node), isDark, style, ink);
          final open = widget.onOpenLink;
          if (open == null || href.isEmpty) {
            spans.addAll(label);
            break;
          }
          final recognizer = TapGestureRecognizer()..onTap = () => open(href);
          _recognizers.add(recognizer);
          spans.add(TextSpan(
            children: label,
            style: TextStyle(color: AppTheme.primaryOf(isDark)),
            recognizer: recognizer,
          ));
        case 'br':
          spans.add(const TextSpan(text: '\n'));
        case 'img':
          final alt = node.attributes['alt'] ?? '';
          spans.add(TextSpan(
            text: alt.isEmpty ? '[图片]' : '[图片：$alt]',
            style: style.copyWith(color: AppInk.tertiary(isDark)),
          ));
        default:
          spans.addAll(_inline(_kids(node), isDark, style, ink));
      }
    }
    return spans;
  }
}
