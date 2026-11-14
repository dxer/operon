import '../protocol/results.dart';
import '../refs.dart';
import 'ax.dart';

/// What one snapshot gives the caller: the page's controls with refs, its text,
/// and an honest list of what was left out.
class Outline {
  const Outline({
    required this.url,
    required this.title,
    required this.lines,
    required this.entries,
    required this.content,
    required this.omitted,
    required this.truncated,
  });

  final String url;
  final String title;

  /// Rendered interactive lines, indented, in reading order.
  final List<String> lines;

  /// The same lines with their refs and node ids, for the caller's own filtering.
  final List<OutlineLine> entries;

  /// Page text worth reading, already shortened per block.
  final List<String> content;

  /// Everything the capture did not show, in words.
  final List<String> omitted;

  /// True when a budget cut the list, so the caller knows to scroll rather than
  /// assume the page is short.
  final bool truncated;

  bool get isEmpty => lines.isEmpty && content.isEmpty;

  /// The text a model reads. Stable enough to diff between two snapshots.
  String render({bool includeContent = true}) {
    final buffer = StringBuffer()
      ..writeln('页面: $title')
      ..writeln('地址: $url')
      ..writeln();
    if (lines.isEmpty) {
      buffer.writeln('(没有可操作的元素)');
    } else {
      buffer.writeln('可操作元素:');
      for (final line in lines) {
        buffer.writeln(line);
      }
    }
    if (includeContent && content.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('页面文字:');
      for (final block in content) {
        buffer.writeln(block);
      }
    }
    if (omitted.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('未显示的部分:');
      for (final note in omitted) {
        buffer.writeln('- $note');
      }
    }
    return buffer.toString().trimRight();
  }
}

/// Turns accessibility nodes into the outline.
///
/// The walk is breadth-first in document order and depth-first per subtree, so
/// the printed order matches what a person reads. Structural wrappers collapse,
/// text that repeats a name is dropped, and every omission is counted instead of
/// silently cut.
class OutlineBuilder {
  OutlineBuilder({
    this.maxEntries = 180,
    this.maxContentBlocks = 14,
    this.maxContentChars = 4000,
    this.maxBlockChars = 240,
    this.maxDepth = 6,
  });

  final int maxEntries;
  final int maxContentBlocks;
  final int maxContentChars;
  final int maxBlockChars;
  final int maxDepth;

  Outline build({
    required List<AxNode> nodes,
    required RefRegistry refs,
    required String url,
    required String title,
  }) {
    final byId = <String, AxNode>{for (final node in nodes) node.nodeId: node};
    final children = <String, List<AxNode>>{};
    final roots = <AxNode>[];

    for (final node in nodes) {
      final parentId = node.parentId;
      if (parentId == null || !byId.containsKey(parentId)) {
        roots.add(node);
      } else {
        children.putIfAbsent(parentId, () => []).add(node);
      }
    }

    final lines = <String>[];
    final entries = <OutlineLine>[];
    final content = <String>[];
    final omitted = <String>[];
    var contentChars = 0;
    var droppedEntries = 0;
    var unaddressable = 0;
    var droppedContent = 0;
    var sawFrame = false;

    void visit(AxNode node, int depth) {
      if (node.ignored) {
        for (final child in children[node.nodeId] ?? const <AxNode>[]) {
          visit(child, depth);
        }
        return;
      }

      final kids = children[node.nodeId] ?? const <AxNode>[];
      final isStructural = structuralRoles.contains(node.role);
      final named = node.name.trim().isNotEmpty;

      if (isStructural && !named) {
        for (final child in kids) {
          visit(child, depth);
        }
        return;
      }

      if (node.isInteractive) {
        final backendNodeId = node.backendNodeId;
        if (backendNodeId == null) {
          // Without a node id there is nothing to address, so it is reported as
          // unaddressable rather than given a ref that cannot work.
          unaddressable++;
          for (final child in kids) {
            visit(child, depth);
          }
          return;
        }
        if (lines.length >= maxEntries) {
          droppedEntries++;
          return;
        }
        final ref = refs.register(
          sessionId: node.sessionId,
          backendNodeId: backendNodeId,
          role: node.role,
          name: node.name,
          disabled: node.flag('disabled'),
          editable: editableRoles.contains(node.role),
        );
        final entry = OutlineLine(
          ref: ref,
          role: node.role,
          name: node.name,
          value: _maskedValue(node),
          states: _statesOf(node),
          depth: depth.clamp(0, maxDepth),
          backendNodeId: backendNodeId,
          frameId: node.sessionId,
        );
        entries.add(entry);
        lines.add(entry.render());
        sawFrame = sawFrame || node.role == 'Iframe';
        // A control's own text is its name; visiting its children again would
        // print the label a second time.
        return;
      }

      if (contentRoles.contains(node.role) && named) {
        if (content.length >= maxContentBlocks || contentChars >= maxContentChars) {
          droppedContent++;
        } else {
          final text = _oneLine(node.name, limit: maxBlockChars);
          if (text.isNotEmpty && !content.contains(text)) {
            content.add(node.role == 'heading' ? '# $text' : text);
            contentChars += text.length;
          }
        }
        for (final child in kids) {
          visit(child, depth);
        }
        return;
      }

      if (named && !isStructural) {
        // A named container (a landmark, a list with a label) is worth a header
        // line: it orients the caller without costing a ref.
        if (lines.length < maxEntries) {
          final text = _oneLine(node.name);
          if (text.isNotEmpty) {
            lines.add('${'  ' * depth.clamp(0, maxDepth)}$text');
          }
        }
      }

      for (final child in kids) {
        visit(child, depth + 1);
      }
    }

    for (final root in roots) {
      visit(root, 0);
    }

    if (droppedEntries > 0) {
      omitted.add('还有 $droppedEntries 个元素未显示（超出单次快照上限 $maxEntries），滚动或用 find 定位');
    }
    if (unaddressable > 0) {
      omitted.add('有 $unaddressable 个控件没有可定位的节点标识，无法直接操作');
    }
    if (droppedContent > 0) {
      omitted.add('还有 $droppedContent 段文字未显示（超出内容上限）');
    }
    if (sawFrame) {
      omitted.add('页面包含 iframe；其内部控件在子 frame 中单独列出');
    }

    return Outline(
      url: url,
      title: title,
      lines: lines,
      entries: entries,
      content: content,
      omitted: omitted,
      truncated: droppedEntries > 0 || droppedContent > 0,
    );
  }

  /// Password-like fields never put their value in the outline.
  String? _maskedValue(AxNode node) {
    final value = node.value;
    if (value == null || value.isEmpty) return null;
    if (node.flag('protected') || _sensitive(node)) return '•••';
    return _oneLine(value, limit: 60);
  }

  bool _sensitive(AxNode node) {
    final label = node.name.toLowerCase();
    if (label.contains('password') ||
        label.contains('passwd') ||
        label.contains('密码') ||
        label.contains('cvv') ||
        label.contains('cvc') ||
        label.contains('验证码') ||
        label.contains('verification code') ||
        label.contains('one-time') ||
        label.contains('card number') ||
        label.contains('卡号')) {
      return true;
    }
    return false;
  }

  List<String> _statesOf(AxNode node) {
    final states = <String>[];
    if (node.flag('disabled')) states.add('disabled');
    if (node.flag('readonly')) states.add('readonly');
    if (node.flag('required')) states.add('required');
    final checked = node.properties['checked'];
    if (checked == true || checked == 'true') {
      states.add('checked');
    } else if (checked == 'mixed') {
      states.add('mixed');
    }
    if (node.flag('selected')) states.add('selected');
    final expanded = node.optionalFlag('expanded');
    if (expanded != null) states.add(expanded ? 'expanded' : 'collapsed');
    return states;
  }

  static String _oneLine(String text, {int limit = 0}) {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final cap = limit > 0 ? limit : 0;
    if (cap > 0 && flat.length > cap) return '${flat.substring(0, cap - 1)}…';
    return flat;
  }
}
