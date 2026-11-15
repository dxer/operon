part of 'session.dart';

extension _SessionGeometry on ControlSession {
  Future<({double x, double y})> _viewportPoint(RefRecord record) async {
    final box = await _measure(record);
    if (box == null) {
      throw ControlException(
        ControlErrorCode.notVisible,
        '元素 [${record.ref}] 当前不可见',
        hint: '它可能在视口外或已隐藏；滚动或用 find 重新定位',
        details: {'ref': record.ref},
      );
    }
    return (x: box.x, y: box.y);
  }

  /// Where the element is now, in viewport coordinates, or null when it has no
  /// area on screen.
  Future<MeasuredBox?> _measure(RefRecord record) async {
    final quads = await _contentQuads(record);
    if (quads.isEmpty) return null;
    final best = quads.reduce((a, b) => a.area >= b.area ? a : b);
    if (best.area <= 0) return null;
    final scroll = await _scrollOffset();
    final viewport = best.toViewport(scroll.x, scroll.y);
    final center = viewport.center;
    return (
      x: center.x,
      y: center.y,
      left: viewport.left,
      top: viewport.top,
      width: viewport.width,
      height: viewport.height,
      inViewport: scroll.contains(center.x, center.y),
    );
  }

  /// Scrolls the element into view before anything is dispatched.
  Future<void> scrollIntoView(RefRecord record) async {
    try {
      await _connection.send(
        'DOM.scrollIntoViewIfNeeded',
        params: {'backendNodeId': record.backendNodeId},
        sessionId: record.sessionId,
      );
    } on ControlException {
      // An older WebView build may not have it.
    }
  }

  /// Tells the UI where the next event goes, and how big the target is.
  ///
  /// Called once the box has been measured and accepted, before anything is
  /// dispatched. The ring is a promise about where the event will land, so it
  /// must not be drawn before the layer knows — and it must not survive a
  /// refusal either, which is why a failed check never reaches here.
  void _announceGesture(
    RefRecord record,
    ({double x, double y, double width, double height}) point,
  ) {
    onGesture?.call(GestureTarget(
      x: point.x,
      y: point.y,
      width: point.width,
      height: point.height,
      label: record.label,
    ));
  }

  /// Waits until the element can be acted on, then says where.
  Future<({double x, double y, double width, double height})> _actionablePoint(
    RefRecord record, {
    Duration budget = const Duration(milliseconds: 1500),
  }) async {
    if (record.disabled) {
      throw ControlException(
        ControlErrorCode.disabled,
        '元素 [${record.ref}] 当前是禁用状态',
        hint: '等页面状态变化后再操作，或换一个入口',
        details: {'ref': record.ref, 'role': record.role},
      );
    }
    final deadline = DateTime.now().add(budget);
    ControlException? last;
    MeasuredBox? previous;
    var scrolled = false;

    while (true) {
      final box = await _measure(record);
      if (box == null) {
        last = ControlException(
          ControlErrorCode.notVisible,
          '元素 [${record.ref}] 当前不可见',
          hint: '它可能在视口外或已隐藏；滚动或用 find 重新定位',
          details: {'ref': record.ref},
        );
      } else if (!box.inViewport) {
        if (!scrolled) {
          scrolled = true;
          await scrollIntoView(record);
          previous = null;
          continue;
        }
        last = ControlException(
          ControlErrorCode.notVisible,
          '元素 [${record.ref}] 不在可见区域内',
          hint: '它可能被固定在视口外，或页面不接受程序滚动；先用 scroll 把页面滚到它附近',
          details: {'ref': record.ref, 'x': box.x, 'y': box.y},
        );
      } else if (previous != null && !_sameBox(previous, box)) {
        last = ControlException(
          ControlErrorCode.notStable,
          '元素 [${record.ref}] 位置在变化（动画或自动滚动）',
          hint: '等页面稳定后再试；也可以在动作前先 wait 一下',
          details: {'ref': record.ref},
        );
      } else {
        final top = await _nodeAt(box.x, box.y, record.sessionId);
        final reachable = top == null ||
            top == record.backendNodeId ||
            await _isWithin(top, record.backendNodeId, record.sessionId);
        if (reachable) {
          return (x: box.x, y: box.y, width: box.width, height: box.height);
        }
        final what = await _describeNode(top, record.sessionId);
        last = ControlException(
          ControlErrorCode.notHittable,
          '元素 [${record.ref}] 被其它元素遮挡（$what）',
          hint: '先关闭弹层或滚动到可见位置，再点一次',
          details: {'ref': record.ref, 'x': box.x, 'y': box.y},
        );
      }

      if (box != null) previous = box;
      if (!DateTime.now().isBefore(deadline)) {
        throw last;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  bool _sameBox(MeasuredBox a, MeasuredBox b) =>
      (a.left - b.left).abs() < 0.5 &&
      (a.top - b.top).abs() < 0.5 &&
      (a.width - b.width).abs() < 0.5 &&
      (a.height - b.height).abs() < 0.5;

  Future<List<Quad>> _contentQuads(RefRecord record) async {
    try {
      final result = await _connection.send(
        'DOM.getContentQuads',
        params: {'backendNodeId': record.backendNodeId},
        sessionId: record.sessionId,
      );
      final raw = result['quads'];
      if (raw is List) {
        final quads = raw.map(Quad.fromRaw).whereType<Quad>().toList();
        if (quads.isNotEmpty) return quads;
      }
    } on ControlException {
      // Fall back to the box model: inline nodes report no content quads.
    }
    try {
      final result = await _connection.send(
        'DOM.getBoxModel',
        params: {'backendNodeId': record.backendNodeId},
        sessionId: record.sessionId,
      );
      final model = result['model'];
      if (model is Map) {
        final content = model['content'];
        if (content is List) {
          final values =
              content.whereType<num>().map((value) => value.toDouble()).toList();
          final quad = Quad.fromBoxModel(values);
          if (quad != null) return [quad];
        }
      }
    } on ControlException {
      return const [];
    }
    return const [];
  }

  Future<int?> _nodeAt(double x, double y, String? sessionId) async {
    try {
      final result = await _connection.send(
        'DOM.getNodeForLocation',
        params: {'x': x, 'y': y, 'includeUserAgentShadowDOM': true},
        sessionId: sessionId,
      );
      return (result['backendNodeId'] as num?)?.toInt();
    } on ControlException {
      return null;
    }
  }

  Future<bool> _isWithin(int candidate, int target, String? sessionId) async {
    if (candidate == target) return true;
    try {
      final result = await _connection.send(
        'DOM.describeNode',
        params: {'backendNodeId': candidate, 'depth': 12},
        sessionId: sessionId,
      );
      final node = result['node'];
      if (node is! Map) return false;
      return _containsBackendId(node, target);
    } on ControlException {
      return false;
    }
  }

  bool _containsBackendId(Map node, int target) {
    if ((node['backendNodeId'] as num?)?.toInt() == target) return true;
    final children = node['children'];
    if (children is List) {
      for (final child in children) {
        if (child is Map && _containsBackendId(child, target)) return true;
      }
    }
    final shadowRoots = node['shadowRoots'];
    if (shadowRoots is List) {
      for (final root in shadowRoots) {
        if (root is Map && _containsBackendId(root, target)) return true;
      }
    }
    return false;
  }

  Future<String> _describeNode(int backendNodeId, String? sessionId) async {
    try {
      final result = await _connection.send(
        'DOM.describeNode',
        params: {'backendNodeId': backendNodeId},
        sessionId: sessionId,
      );
      final node = result['node'];
      if (node is Map) {
        final name =
            (node['localName'] as String?) ?? (node['nodeName'] as String?) ?? '元素';
        final attributes = node['attributes'];
        if (attributes is List) {
          for (var index = 0; index + 1 < attributes.length; index += 2) {
            if (attributes[index] == 'class' &&
                attributes[index + 1] is String) {
              return '<$name class="${attributes[index + 1]}">';
            }
          }
        }
        return '<$name>';
      }
    } on ControlException {
      // Best-effort description.
    }
    return '其它元素';
  }

  Future<({double width, double height})> _viewport() async {
    try {
      final metrics = await _connection.send('Page.getLayoutMetrics');
      final viewport = metrics['cssLayoutViewport'] ?? metrics['layoutViewport'];
      if (viewport is Map) {
        return (
          width: (viewport['clientWidth'] as num?)?.toDouble() ?? 400,
          height: (viewport['clientHeight'] as num?)?.toDouble() ?? 800,
        );
      }
    } on ControlException {
      // Keep the fallback.
    }
    return (width: 400.0, height: 800.0);
  }

  Future<ScrollOffset> _scrollOffset() async {
    try {
      final metrics = await _connection.send('Page.getLayoutMetrics');
      return ScrollOffset.fromLayoutMetrics(metrics);
    } on ControlException {
      return ScrollOffset.zero;
    }
  }

  Future<({bool changed, List<String> changes, String url})> _settleAndObserve(
    String urlBefore,
    List<String> linesBefore, {
    bool waitForNavigation = false,
    int settleMs = 900,
  }) async {
    await _settle(waitForNavigation: waitForNavigation, budgetMs: settleMs);
    final url = await currentUrl();
    List<String> lines;
    try {
      final outline = await snapshot(includeContent: false);
      lines = outline.lines;
    } on ControlException {
      return (changed: url != urlBefore, changes: const <String>[], url: url);
    }
    final changes = diffLines(linesBefore, lines);
    final changed = changes.isNotEmpty || url != urlBefore;
    return (changed: changed, changes: changes, url: url);
  }

  Future<void> _settle({bool waitForNavigation = false, int budgetMs = 900}) async {
    if (waitForNavigation) {
      try {
        await _connection.events
            .firstWhere((event) => event.method == 'Page.loadEventFired')
            .timeout(const Duration(seconds: 15));
      } on TimeoutException {
        _note('提交后未等到页面跳转，按当前页面继续判断');
      }
    }
    final deadline = DateTime.now().add(Duration(milliseconds: budgetMs));
    List<String> previous = const [];
    var first = true;
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      List<String> current;
      try {
        current = (await snapshot(includeContent: false)).lines;
      } on ControlException {
        return;
      }
      if (!first && _sameLines(previous, current)) return;
      previous = current;
      first = false;
    }
  }

  bool _sameLines(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }
}
