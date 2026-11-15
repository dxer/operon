import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operon/services/storage_service.dart';
import 'package:operon/views/settings/ai_policy_settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
  });

  testWidgets('background execution is on by default and can be turned off',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AiPolicySettingsPage()));
    await tester.pumpAndSettle();

    expect(find.text('后台继续执行'), findsOneWidget);
    final tile = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, '后台继续执行'),
    );
    expect(tile.value, isTrue);

    await tester.tap(find.text('后台继续执行'));
    await tester.pumpAndSettle();

    final storage = await StorageService.getInstance();
    expect(storage.getBackgroundTaskMode(), isFalse);
    expect(
      tester
          .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '后台继续执行'))
          .value,
      isFalse,
    );
  });

  testWidgets('a saved choice is what the page shows next time',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {'pref_background_task_mode': false});
    StorageService.resetForTest();

    await tester.pumpWidget(const MaterialApp(home: AiPolicySettingsPage()));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '后台继续执行'))
          .value,
      isFalse,
    );
  });
}
