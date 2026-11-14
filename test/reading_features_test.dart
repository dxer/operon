import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operon/config/app_theme.dart';
import 'package:operon/services/storage_service.dart';
import 'package:operon/views/settings/browsing_settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<StorageService> freshStorage(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  StorageService.resetForTest();
  return StorageService.getInstance();
}

void main() {
  group('reading feature switches', () {
    test('all three are on for a fresh install', () async {
      final storage = await freshStorage({});
      expect(storage.getReadingModeEnabled(), isTrue);
      expect(storage.getSelectionMenuEnabled(), isTrue);
      expect(storage.getPageSummaryEnabled(), isTrue);
    });

    test('each one persists independently', () async {
      final storage = await freshStorage({});

      await storage.saveReadingModeEnabled(false);
      expect(storage.getReadingModeEnabled(), isFalse);
      expect(storage.getSelectionMenuEnabled(), isTrue);
      expect(storage.getPageSummaryEnabled(), isTrue);

      await storage.savePageSummaryEnabled(false);
      expect(storage.getReadingModeEnabled(), isFalse);
      expect(storage.getPageSummaryEnabled(), isFalse);

      await storage.saveReadingModeEnabled(true);
      expect(storage.getReadingModeEnabled(), isTrue);
      expect(storage.getPageSummaryEnabled(), isFalse);
    });

    test('a value written earlier is read back after a restart', () async {
      SharedPreferences.setMockInitialValues({});
      StorageService.resetForTest();
      final first = await StorageService.getInstance();
      await first.saveSelectionMenuEnabled(false);

      // A second start of the app reads what the first one wrote.
      StorageService.resetForTest();
      final second = await StorageService.getInstance();
      expect(second.getSelectionMenuEnabled(), isFalse);
    });
  });

  testWidgets('settings shows the three switches and writes them through',
      (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final storage = await freshStorage({});
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme.copyWith(
        splashFactory: InkRipple.splashFactory,
      ),
      home: const BrowsingSettingsPage(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('阅读与摘要'), findsOneWidget);
    expect(find.text('纯净阅读'), findsOneWidget);
    expect(find.text('划词操作'), findsOneWidget);
    expect(find.text('页面总结'), findsOneWidget);

    await tester.tap(find.text('划词操作'));
    await tester.pumpAndSettle();

    expect(storage.getSelectionMenuEnabled(), isFalse);
    // The other two are untouched: the switches are independent.
    expect(storage.getReadingModeEnabled(), isTrue);
    expect(storage.getPageSummaryEnabled(), isTrue);
    expect(tester.takeException(), isNull);
  });
}
