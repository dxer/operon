import 'package:flutter_test/flutter_test.dart';
import 'package:operon/control/control.dart';
import 'package:operon/control/protocol/errors.dart';
import 'package:operon/control/tab_host.dart';
import 'package:operon/control/transport/endpoint.dart' show CdpTarget;

import 'support/fake_devtools.dart';

// Tabs, from the agent's side.
//
// `switch_tab` used to move the CDP session and stop there, so the agent acted
// on a page the user could not see. `close_tab` and `navigate(newTab:)` cannot
// exist without the app's tab strip at all. Both halves are pinned here.

FakePage newsPage({String id = 'T1'}) {
  final page = FakePage(
    id: id,
    url: 'https://news.example.com/',
    title: '新闻首页',
    nodes: const [
      FakePageNode(backendNodeId: 1, role: 'textbox', name: '搜索', editable: true),
      FakePageNode(backendNodeId: 2, role: 'link', name: '下一条'),
    ],
  );
  page.boxes
    ..[1] = const FakeBox(20, 40, 200, 32)
    ..[2] = const FakeBox(20, 120, 120, 24);
  return page;
}

FakePage docsPage({String id = 'T2'}) {
  final page = FakePage(
    id: id,
    url: 'https://docs.example.com/guide',
    title: '文档',
    nodes: const [FakePageNode(backendNodeId: 10, role: 'heading', name: '指南')],
  );
  page.boxes[10] = const FakeBox(20, 20, 200, 30);
  return page;
}

void main() {
  late FakeDevTools fake;
  late Control control;

  tearDown(() async {
    await control.detach();
    await fake.close();
  });

  group('clear', () {
    test('empties the field through the same editing pipeline', () async {
      fake = await FakeDevTools.start(newsPage());
      control = await Control.attach(connect: fake.connect);
      await control.execute('snapshot');
      await control.execute('type', {'ref': 'a1', 'text': '关键词'});
      expect(fake.page.typedText.join(), '关键词');

      final result = await control.execute('clear', {'ref': 'a1'});

      expect(result.ok, isTrue, reason: result.error?.toString());
      expect(fake.page.typedText, isEmpty);
      // Its own words: 「已输入空字符串」 would describe the implementation
      // rather than what happened.
      expect(result.text, contains('已清空'));
    });

    test('a clear with no ref is a bad call, not a silent no-op', () async {
      fake = await FakeDevTools.start(newsPage());
      control = await Control.attach(connect: fake.connect);

      final result = await control.execute('clear');

      expect(result.ok, isFalse);
      expect(result.error?.code, ControlErrorCode.badArguments);
    });
  });

  group('attach', () {
    test('shows the page it attached to before the first action', () async {
      fake = await FakeDevTools.start(newsPage());
      final activated = <CdpTarget>[];
      control = await Control.attach(
        connect: fake.connect,
        tabHost: TabHost(activate: (page) async {
          activated.add(page);
          return true;
        }),
      );

      // Attaching is not showing. Without this the run can work on a tab the
      // user is not looking at, and the working frame pulses over the wrong one.
      expect(activated, hasLength(1));
      expect(activated.single.id, 'T1');
    });

    test('a start-page hint attaches to the start page, not another tab',
        () async {
      final start = FakePage(id: 'T0', url: 'about:blank', title: '新标签页');
      fake = await FakeDevTools.start(newsPage(), also: [start]);

      control = await Control.attach(
        connect: fake.connect,
        urlHint: 'operon://newtab',
      );

      // The start page is an `about:blank` WebView. Skipping blank targets is
      // right when the hint names a real page and wrong when it names this one:
      // the run then drove whichever tab happened to be first.
      expect(control.session.target.id, 'T0');
    });
  });

  group('switch_tab', () {
    test('tells the app to follow, because the user cannot see CDP', () async {
      fake = await FakeDevTools.start(newsPage(), also: [docsPage()]);
      final activated = <CdpTarget>[];
      control = await Control.attach(
        connect: fake.connect,
        tabHost: TabHost(activate: (page) async {
          activated.add(page);
          return true;
        }),
      );
      // Attaching already asked once, so the record starts from the attach.
      activated.clear();
      await control.execute('snapshot');

      final result = await control.execute('switch_tab', {'tabId': 'T2'});

      expect(result.ok, isTrue, reason: result.error?.toString());
      expect(activated, hasLength(1));
      expect(activated.single.id, 'T2');
      expect(control.session.target.id, 'T2');
    });

    test('says so when the app could not move its own tab strip', () async {
      fake = await FakeDevTools.start(newsPage(), also: [docsPage()]);
      control = await Control.attach(
        connect: fake.connect,
        tabHost: TabHost(activate: (_) async => false),
      );
      await control.execute('snapshot');

      final result = await control.execute('switch_tab', {'tabId': 'T2'});

      expect(result.ok, isTrue);
      // The layer did switch; the screen did not. The model has to know which
      // half happened, or it will describe a page the user never saw.
      expect(result.text, contains('界面上没能切到'));
    });

    test('does not bother the app when it is already there', () async {
      fake = await FakeDevTools.start(newsPage(), also: [docsPage()]);
      var calls = 0;
      control = await Control.attach(
        connect: fake.connect,
        tabHost: TabHost(activate: (_) async {
          calls++;
          return true;
        }),
      );
      final afterAttach = calls;
      await control.execute('snapshot');

      final result = await control.execute('switch_tab', {'tabId': 'T1'});

      expect(result.text, contains('已经在这个标签页上'));
      expect(calls, afterAttach, reason: 'switching to the page already shown asks nothing');
    });
  });

  group('close_tab', () {
    test('without the app there is nothing to close', () async {
      fake = await FakeDevTools.start(newsPage(), also: [docsPage()]);
      control = await Control.attach(connect: fake.connect);
      await control.execute('snapshot');

      final result = await control.execute('close_tab', {'tabId': 'T2'});

      expect(result.ok, isFalse);
      expect(result.data?['reason'], 'no-tab-host');
    });

    test('the last tab is not closed', () async {
      fake = await FakeDevTools.start(newsPage());
      control = await Control.attach(
        connect: fake.connect,
        tabHost: TabHost(close: (_) async => true),
      );
      await control.execute('snapshot');

      final result = await control.execute('close_tab');

      expect(result.ok, isFalse);
      expect(result.data?['reason'], 'last-tab');
    });

    test('another tab goes away and the session stays on this one', () async {
      fake = await FakeDevTools.start(newsPage(), also: [docsPage()]);
      final closed = <String>[];
      control = await Control.attach(
        connect: fake.connect,
        tabHost: TabHost(close: (page) async {
          closed.add(page.id);
          return true;
        }),
      );
      await control.execute('snapshot');

      final result = await control.execute('close_tab', {'tabId': 'T2'});

      expect(result.ok, isTrue, reason: result.error?.toString());
      expect(closed, ['T2']);
      expect(control.session.target.id, 'T1');
    });

    test('closing the current tab moves off it first, then closes', () async {
      fake = await FakeDevTools.start(newsPage(), also: [docsPage()]);
      final order = <String>[];
      control = await Control.attach(
        connect: fake.connect,
        tabHost: TabHost(
          activate: (page) async {
            order.add('activate:${page.id}');
            return true;
          },
          close: (page) async {
            order.add('close:${page.id}');
            return true;
          },
        ),
      );
      // Attaching already showed T1; the order under test starts after that.
      order.clear();
      await control.execute('snapshot');

      final result = await control.execute('close_tab', {'tabId': 'T1'});

      expect(result.ok, isTrue, reason: result.error?.toString());
      // Attaching to a page that is about to disappear would leave every later
      // call failing at once.
      expect(order, ['activate:T2', 'close:T1']);
      expect(control.session.target.id, 'T2');
    });

    test('a refusal from the app is reported as one', () async {
      fake = await FakeDevTools.start(newsPage(), also: [docsPage()]);
      control = await Control.attach(
        connect: fake.connect,
        tabHost: TabHost(close: (_) async => false),
      );
      await control.execute('snapshot');

      final result = await control.execute('close_tab', {'tabId': 'T2'});

      expect(result.ok, isFalse);
      expect(result.data?['reason'], 'refused');
    });
  });

  group('navigate with newTab', () {
    test('without the app it says so instead of pretending', () async {
      fake = await FakeDevTools.start(newsPage());
      control = await Control.attach(connect: fake.connect);
      await control.execute('snapshot');

      final result = await control.execute(
        'navigate',
        {'url': 'https://example.com/', 'newTab': true},
      );

      expect(result.ok, isFalse);
      expect(result.data?['reason'], 'no-tab-host');
    });

    test('opens a tab and moves the layer onto it', () async {
      fake = await FakeDevTools.start(newsPage(), also: [docsPage()]);
      control = await Control.attach(
        connect: fake.connect,
        tabHost: TabHost(open: (url) async {
          fake.addPage(FakePage(
            id: 'T3',
            url: url,
            title: '新页面',
            nodes: const [
              FakePageNode(backendNodeId: 20, role: 'heading', name: '新页面'),
            ],
          ));
        }),
      );
      await control.execute('snapshot');

      final result = await control.execute(
        'navigate',
        {'url': 'https://example.com/fresh', 'newTab': true},
      );

      expect(result.ok, isTrue, reason: result.error?.toString());
      expect(control.session.target.id, 'T3');
      expect(result.text, contains('新标签页'));
    });

    test('the plain navigate still replaces the current page', () async {
      fake = await FakeDevTools.start(newsPage(), also: [docsPage()]);
      var opened = 0;
      control = await Control.attach(
        connect: fake.connect,
        tabHost: TabHost(open: (_) async => opened++),
      );
      await control.execute('snapshot');

      await control.execute('navigate', {'url': 'https://example.com/next'});

      expect(opened, 0);
      expect(control.session.target.id, 'T1');
      expect(fake.page.url, 'https://example.com/next');
    });
  });
}
