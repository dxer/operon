import 'package:flutter_test/flutter_test.dart';
import 'package:operon/control/control.dart';
import 'package:operon/control/protocol/errors.dart';
import 'package:operon/control/protocol/results.dart';

import 'support/fake_devtools.dart';

/// End-to-end scenarios for the control layer, over a fake DevTools server.
///
/// Everything between the socket and the receipt runs for real: the HTTP
/// discovery with a chunked body, the WebSocket upgrade, JSON-RPC, the
/// accessibility outline, refs, geometry, the actionability checks and the diff.
/// Only the page is fake.

FakePage searchPage() {
  final page = FakePage(
    url: 'https://news.example.com/',
    title: '新闻首页',
    nodes: const [
      FakePageNode(backendNodeId: 1, role: 'textbox', name: '搜索', editable: true),
      FakePageNode(backendNodeId: 2, role: 'button', name: '搜索按钮'),
      FakePageNode(backendNodeId: 3, role: 'link', name: '下一条'),
      FakePageNode(backendNodeId: 4, role: 'button', name: '已停用的按钮', disabled: true),
    ],
  );
  page.boxes
    ..[1] = const FakeBox(20, 40, 200, 32)
    ..[2] = const FakeBox(230, 40, 60, 32)
    ..[3] = const FakeBox(20, 120, 120, 24)
    ..[4] = const FakeBox(20, 200, 120, 32);
  return page;
}

Future<Control> attachTo(FakePage page, FakeDevTools fake) =>
    Control.attach(connect: fake.connect);

void main() {
  late FakeDevTools fake;
  late Control control;

  tearDown(() async {
    await control.detach();
    await fake.close();
  });

  test('a snapshot turns the accessibility tree into refs', () async {
    final page = searchPage();
    fake = await FakeDevTools.start(page);
    control = await attachTo(page, fake);

    final result = await control.execute('snapshot');
    expect(result.ok, isTrue, reason: result.error?.toString());
    final text = result.text ?? '';
    expect(text, contains('[a1]'));
    expect(text, contains('搜索按钮'));
    // The disabled button is still listed: the model should see why it cannot
    // be used rather than wonder where the button went.
    expect(text, contains('已停用'));
    expect((result.data!['elements'] as int), greaterThan(2));
  });

  test('a click dispatches real input at the element center', () async {
    final page = searchPage();
    fake = await FakeDevTools.start(page);
    control = await attachTo(page, fake);
    await control.execute('snapshot');

    final clicked = <String>[];
    page.onClick = (node) => clicked.add(node.name);

    final result = await control.execute('click', {'ref': 'a2'});
    expect(result.ok, isTrue, reason: result.error?.toString());
    expect(clicked, ['搜索按钮']);
    final receipt = result.receipt!;
    expect(receipt.delivery, Delivery.delivered);
    expect(receipt.elapsed, isNotNull);
    expect(fake.countOf('Input.dispatchTouchEvent') + fake.countOf('Input.dispatchMouseEvent'),
        greaterThan(0));
  });

  test('a click that changes nothing says so instead of claiming success', () async {
    final page = searchPage();
    fake = await FakeDevTools.start(page);
    control = await attachTo(page, fake);
    await control.execute('snapshot');

    final result = await control.execute('click', {'ref': 'a3'});
    expect(result.ok, isTrue);
    expect(result.receipt!.delivery, Delivery.delivered);
    expect(result.receipt!.pageReacted, isFalse);
  });

  test('a covered element is refused before anything is dispatched', () async {
    final page = searchPage();
    // A banner sits on top of the button.
    page.boxes[2] = const FakeBox(230, 40, 60, 32);
    page.nodes = [
      ...page.nodes,
      const FakePageNode(backendNodeId: 9, role: 'generic', name: '覆盖层'),
    ];
    page.boxes[9] = const FakeBox(0, 0, 400, 800);
    fake = await FakeDevTools.start(page);
    control = await attachTo(page, fake);
    await control.execute('snapshot');

    final before = fake.countOf('Input.dispatchTouchEvent') + fake.countOf('Input.dispatchMouseEvent');
    final result = await control.execute('click', {'ref': 'a2'});
    final after = fake.countOf('Input.dispatchTouchEvent') + fake.countOf('Input.dispatchMouseEvent');
    expect(result.ok, isFalse);
    expect(result.error!.code, ControlErrorCode.notHittable);
    expect(after, before, reason: 'nothing may be dispatched to a covered target');
  });

  test('a disabled control is refused with a typed error', () async {
    final page = searchPage();
    fake = await FakeDevTools.start(page);
    control = await attachTo(page, fake);
    await control.execute('snapshot');

    final result = await control.execute('click', {'ref': 'a4'});
    expect(result.ok, isFalse);
    expect(result.error!.code, ControlErrorCode.disabled);
  });

  test('a stale ref fails closed instead of hitting whatever is there now', () async {
    final page = searchPage();
    fake = await FakeDevTools.start(page);
    control = await attachTo(page, fake);
    await control.execute('snapshot');

    // The page navigates: every ref from before is now a guess.
    page.nodes = const [FakePageNode(backendNodeId: 20, role: 'button', name: '新的按钮')];
    page.boxes
      ..clear()
      ..[20] = const FakeBox(10, 10, 80, 30);
    await control.execute('navigate', {'url': 'https://news.example.com/next'});

    final result = await control.execute('click', {'ref': 'a2'});
    expect(result.ok, isFalse);
    expect(
      result.error!.code,
      anyOf(ControlErrorCode.staleRef, ControlErrorCode.unknownRef),
    );
  });

  test('typing goes through the editing pipeline', () async {
    final page = searchPage();
    fake = await FakeDevTools.start(page);
    control = await attachTo(page, fake);
    await control.execute('snapshot');

    final result = await control.execute('type', {'ref': 'a1', 'text': '关键词'});
    expect(result.ok, isTrue, reason: result.error?.toString());
    expect(page.typedText.join(), '关键词');
    expect(result.receipt!.delivery, Delivery.delivered);
  });

  test('typing into a button is refused as not editable', () async {
    final page = searchPage();
    fake = await FakeDevTools.start(page);
    control = await attachTo(page, fake);
    await control.execute('snapshot');

    final result = await control.execute('type', {'ref': 'a2', 'text': 'x'});
    expect(result.ok, isFalse);
    expect(result.error!.code, ControlErrorCode.notEditable);
    expect(page.typedText, isEmpty);
  });

  test('select picks the option the caller meant, and reports it honestly', () async {
    final page = searchPage();
    page.nodes = [
      ...page.nodes,
      const FakePageNode(backendNodeId: 30, role: 'combobox', name: '城市'),
    ];
    page.boxes[30] = const FakeBox(20, 300, 160, 32);
    page.selects[30] = const [
      FakeSelectOption('', '请选择'),
      FakeSelectOption('110000', '北京'),
      FakeSelectOption('310000', '上海'),
    ];
    fake = await FakeDevTools.start(page);
    control = await attachTo(page, fake);
    final snapshot = await control.execute('snapshot');
    expect(snapshot.text, contains('城市'));

    final ref = _refOf(snapshot, '城市');
    final result = await control.execute('select', {'ref': ref, 'optionLabel': '上海'});
    expect(result.ok, isTrue, reason: result.error?.toString());
    expect(page.selectedIndex[30], 2);
    // The popup of a native select cannot be driven by input events, so the
    // receipt must not claim a delivery.
    expect(result.receipt!.delivery, Delivery.unknown);
    expect(result.receipt!.expectedStateReached, isTrue);
    expect(result.receipt!.note, contains('脚本'));
  });

  test('select on something that is not a select explains the way out', () async {
    final page = searchPage();
    fake = await FakeDevTools.start(page);
    control = await attachTo(page, fake);
    final snapshot = await control.execute('snapshot');

    final ref = _refOf(snapshot, '搜索按钮');
    final result = await control.execute('select', {'ref': ref, 'optionLabel': '北京'});
    expect(result.ok, isFalse);
    expect(result.error!.code, ControlErrorCode.notEditable);
    expect(result.error!.hint, contains('click'));
  });

  test('hover keeps the pointer on the element', () async {
    final page = searchPage();
    fake = await FakeDevTools.start(page);
    control = await attachTo(page, fake);
    final snapshot = await control.execute('snapshot');

    final result = await control.execute('hover', {'ref': _refOf(snapshot, '下一条')});
    expect(result.ok, isTrue, reason: result.error?.toString());
    expect(result.receipt!.delivery, Delivery.delivered);
    expect(fake.countOf('Input.dispatchMouseEvent'), greaterThan(0));
  });

  test('a dialog freezes the page and is reported, not clicked through', () async {
    final page = searchPage()..dialogOpen = true;
    fake = await FakeDevTools.start(page);
    control = await attachTo(page, fake);
    await control.execute('snapshot');

    // A dialog freezes the page, so an action is refused with a reason rather
    // than dispatched into a frozen renderer.
    final result = await control.execute('click', {'ref': 'a2'});
    expect(result.ok, isFalse);
    expect(result.error!.code, ControlErrorCode.dialogOpen);

    final handled = await control.execute('handle_dialog', {'accept': true});
    expect(handled.ok, isTrue);
    expect(page.dialogOpen, isFalse);
    expect((await control.execute('snapshot')).ok, isTrue);
  });

  test('a screenshot comes back as base64 the panel can show', () async {
    final page = searchPage();
    fake = await FakeDevTools.start(page);
    control = await attachTo(page, fake);

    final result = await control.execute('screenshot');
    expect(result.ok, isTrue, reason: result.error?.toString());
    expect(result.data!['image'], isA<String>());
  });

  test('an iframe becomes its own session, and its contents are readable', () async {
    final page = searchPage()..childSessionId = 'S1';
    page.frameNodes['S1'] = const [
      FakePageNode(backendNodeId: 41, role: 'textbox', name: '卡号', editable: true),
    ];
    fake = await FakeDevTools.start(page);
    control = await attachTo(page, fake);
    // The fake attaches the child frame right after autoAttach.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final result = await control.execute('snapshot');
    expect(result.ok, isTrue, reason: result.error?.toString());
    expect(result.text, contains('卡号'));
    expect(fake.methods, contains('Runtime.runIfWaitingForDebugger'));
  });

  test('something below the fold is scrolled to, then clicked', () async {
    final page = searchPage();
    page.nodes = [
      ...page.nodes,
      const FakePageNode(backendNodeId: 50, role: 'button', name: '页脚按钮'),
    ];
    page.boxes[50] = const FakeBox(20, 2400, 120, 40);
    fake = await FakeDevTools.start(page);
    control = await attachTo(page, fake);
    final snapshot = await control.execute('snapshot');

    final clicked = <String>[];
    page.onClick = (node) => clicked.add(node.name);
    final result = await control.execute('click', {'ref': _refOf(snapshot, '页脚按钮')});

    expect(result.ok, isTrue, reason: result.error?.toString());
    expect(fake.scrolledIntoView, [50], reason: 'it must be brought on screen first');
    expect(result.receipt!.delivery, Delivery.delivered);
    expect(clicked, ['页脚按钮'], reason: 'and the event must reach it');
  });

  test('an element that stays off screen is never dispatched into nothing', () async {
    final page = searchPage();
    page.nodes = [
      ...page.nodes,
      const FakePageNode(backendNodeId: 51, role: 'button', name: '固定在外'),
    ];
    // No box at all: the page refuses to lay it out where it can be reached.
    page.boxes[51] = const FakeBox(20, 5000, 120, 40);
    fake = await FakeDevTools.start(page);
    control = await attachTo(page, fake);
    final snapshot = await control.execute('snapshot');

    // A page that ignores scrollIntoView keeps reporting the same scroll offset.
    fake.overrides['DOM.scrollIntoViewIfNeeded'] = (_) => const <String, Object?>{};
    final result = await control.execute('click', {'ref': _refOf(snapshot, '固定在外')});
    expect(result.ok, isFalse);
    expect(result.error!.code, ControlErrorCode.notVisible);
  });

  test('back restores the previous history entry', () async {
    final page = searchPage()
      ..history.addAll(['https://news.example.com/', 'https://news.example.com/2'])
      ..historyIndex = 1
      ..url = 'https://news.example.com/2';
    fake = await FakeDevTools.start(page);
    control = await attachTo(page, fake);

    final result = await control.execute('back');
    expect(result.ok, isTrue, reason: result.error?.toString());
    expect(page.historyIndex, 0);
    expect(result.receipt!.urlAfter, 'https://news.example.com/');
    expect(result.receipt!.expectedStateReached, isTrue);
  });

  test('back with nowhere to go says so instead of faking a move', () async {
    final page = searchPage();
    fake = await FakeDevTools.start(page);
    control = await attachTo(page, fake);

    final result = await control.execute('back');
    expect(result.ok, isTrue);
    expect(result.receipt!.expectedStateReached, isFalse);
    expect(result.receipt!.note, contains('没有可回退'));
  });

  test('tabs lists every page and marks the attached one', () async {
    final first = searchPage();
    final second = FakePage(
      id: 'T2',
      url: 'https://mail.example.com/',
      title: '邮箱',
      nodes: const [FakePageNode(backendNodeId: 60, role: 'link', name: '收件箱')],
    )..boxes[60] = const FakeBox(10, 10, 100, 30);
    fake = await FakeDevTools.start(first, also: [second]);
    control = await attachTo(first, fake);

    final result = await control.execute('tabs');
    expect(result.ok, isTrue, reason: result.error?.toString());
    expect(result.text, contains('邮箱'));
    expect(result.text, contains('←当前'));
    final tabs = result.data!['tabs'] as List;
    expect(tabs, hasLength(2));
    expect((tabs.first as Map)['attached'], isTrue);
  });

  test('switch_tab moves the layer onto the other page', () async {
    final first = searchPage();
    final second = FakePage(
      id: 'T2',
      url: 'https://mail.example.com/',
      title: '邮箱',
      nodes: const [FakePageNode(backendNodeId: 60, role: 'link', name: '收件箱')],
    )..boxes[60] = const FakeBox(10, 10, 100, 30);
    fake = await FakeDevTools.start(first, also: [second]);
    control = await attachTo(first, fake);

    final switched = await control.execute('switch_tab', {'tabId': 'T2'});
    expect(switched.ok, isTrue, reason: switched.error?.toString() ?? switched.text);

    final snapshot = await control.execute('snapshot');
    expect(snapshot.text, contains('收件箱'));
    expect(control.url, 'https://mail.example.com/');
  });

  test('switch_tab to a tab that is not there explains what is', () async {
    final page = searchPage();
    fake = await FakeDevTools.start(page);
    control = await attachTo(page, fake);

    final result = await control.execute('switch_tab', {'tabId': 'T9'});
    expect(result.ok, isFalse);
    expect(result.text, contains('找不到'));
    expect(result.data!['ids'], isA<List>());
  });

  test('upload hands files to a file input and reports the count', () async {
    final page = searchPage();
    page.nodes = [
      ...page.nodes,
      const FakePageNode(backendNodeId: 70, role: 'button', name: '选择文件'),
    ];
    page.boxes[70] = const FakeBox(20, 400, 120, 40);
    page.fileInputs.add(70);
    fake = await FakeDevTools.start(page);
    control = await attachTo(page, fake);
    final snapshot = await control.execute('snapshot');

    final result = await control.execute('upload', {
      'ref': _refOf(snapshot, '选择文件'),
      'files': '/sdcard/Download/a.pdf, /sdcard/Download/b.pdf',
    });
    expect(result.ok, isTrue, reason: result.error?.toString());
    expect(page.uploadedFiles[70], hasLength(2));
    expect(result.receipt!.expectedStateReached, isTrue);
    expect(result.receipt!.delivery, Delivery.unknown, reason: 'no input event was dispatched');
  });

  test('upload on a control that is not a file input refuses clearly', () async {
    final page = searchPage();
    fake = await FakeDevTools.start(page);
    control = await attachTo(page, fake);
    final snapshot = await control.execute('snapshot');

    final result = await control.execute('upload', {
      'ref': _refOf(snapshot, '搜索按钮'),
      'files': '/sdcard/Download/a.pdf',
    });
    expect(result.ok, isFalse);
    expect(result.error!.code, ControlErrorCode.notEditable);
    expect(page.uploadedFiles, isEmpty);
  });
}

/// The ref for the outline line whose label contains [label].
String _refOf(ToolResult snapshot, String label) {
  for (final line in snapshot.text!.split('\n')) {
    if (line.contains(label)) {
      final match = RegExp(r'\[(a\d+)\]').firstMatch(line);
      if (match != null) return match.group(1)!;
    }
  }
  fail('快照里没有「$label」：\n${snapshot.text}');
}
