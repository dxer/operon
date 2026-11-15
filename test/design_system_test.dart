// Doc comments above a top-level declaration only; `library;` after imports is
// a directive and would have to come first.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:operon/config/app_tokens.dart';

/// The scales are only worth having if the code keeps using them.
///
/// A design system decays one widget at a time: someone needs "just slightly
/// larger here" and writes `fontSize: 12.5`, which is how this project ended up
/// with 22 type sizes and 18 corner radii. This test reads the source and fails
/// on any size that is not on the scale.
///
/// It is deliberately an allowlist of migrated files rather than the whole of
/// `lib/`: the remaining screens are converted phase by phase, and a test that
/// fails on unstarted work would just be switched off. Add a file here when it
/// is converted.

const _migrated = <String>[
  // First run
  'lib/views/onboarding_page.dart',
  // Shell
  'lib/views/widgets/browser_controls.dart',
  'lib/views/widgets/start_page_view.dart',
  'lib/views/widgets/bottom_toolbar.dart',
  'lib/views/widgets/omnibox_suggestions.dart',
  'lib/views/widgets/find_in_page_bar.dart',
  'lib/views/widgets/agent_working_frame.dart',
  'lib/views/widgets/tabs_overview_sheet.dart',
  // Agent panel
  'lib/views/widgets/agent_bottom_sheet.dart',
  'lib/views/widgets/sheet/header.dart',
  'lib/views/widgets/sheet/body.dart',
  'lib/views/widgets/sheet/result.dart',
  'lib/views/widgets/step_log_view.dart',
  // Lists & sheets
  'lib/views/widgets/extracted_data_sheet.dart',
  'lib/views/widgets/operon_list_row.dart',
  'lib/views/widgets/site_icon.dart',
  'lib/views/widgets/history_bookmarks_sheet.dart',
  'lib/views/widgets/summary_bottom_sheet.dart',
  'lib/views/widgets/selection_action_dialog.dart',
  'lib/views/widgets/agent_confirmation_card.dart',
  'lib/views/settings/settings_page.dart',
  'lib/views/settings/about_settings_page.dart',
];

/// Sizes the type scale allows, in points.
// Sets of doubles cannot be const: `double` overrides `==`.
final _allowedFontSizes = <double>{28, 20, 17, 15, 13, 12, 11};

/// Corner radii the scale allows, plus 2 for text cursors.
final _allowedRadii = <double>{
  AppRadius.chip,
  AppRadius.icon,
  AppRadius.card,
  AppRadius.sheet,
  AppRadius.pill,
  2,
};

double? _number(String raw) => double.tryParse(raw);

Set<double> _matches(String source, RegExp pattern) {
  final values = <double>{};
  for (final match in pattern.allMatches(source)) {
    final value = _number(match.group(1) ?? '');
    if (value != null) values.add(value);
  }
  return values;
}

void main() {
  test('the type scale has seven steps and no duplicates', () {
    final sizes = [
      AppType.display.fontSize,
      AppType.title.fontSize,
      AppType.headline.fontSize,
      AppType.body.fontSize,
      AppType.label.fontSize,
      AppType.caption.fontSize,
      AppType.micro.fontSize,
    ].cast<double>();

    expect(sizes.toSet(), hasLength(sizes.length), reason: 'no two steps match');
    for (final size in sizes) {
      expect(_allowedFontSizes, contains(size));
    }
  });

  test('every style in the scale sets a line height', () {
    for (final style in [
      AppType.display,
      AppType.title,
      AppType.headline,
      AppType.body,
      AppType.label,
      AppType.caption,
      AppType.micro,
    ]) {
      expect(style.height, isNotNull,
          reason: 'Chinese text at the default line height reads cramped');
      expect(style.height!, greaterThanOrEqualTo(1.2));
    }
  });

  test('body copy is at least 15pt', () {
    // The screens used to run at 11–12pt for real sentences.
    expect(AppType.body.fontSize, greaterThanOrEqualTo(15));
  });

  test('the ink floor keeps small text above AA', () {
    // #F3F2F1 at 55% on #292929 is about 4.6:1. Anything dimmer fails AA at
    // the sizes the tertiary tone is used on.
    expect(AppInk.tertiary(true).a, greaterThanOrEqualTo(0.55));
    expect(AppInk.tertiary(false).a, greaterThanOrEqualTo(0.55));
    expect(AppInk.secondary(true).a, greaterThan(AppInk.tertiary(true).a));
  });

  group('migrated files only use the scale', () {
    for (final path in _migrated) {
      test(path, () {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: '$path is missing');

        final source = file.readAsStringSync();
        final sizes = _matches(source, RegExp(r'fontSize:\s*([0-9.]+)'));
        expect(sizes.difference(_allowedFontSizes), isEmpty,
            reason: '$path uses font sizes outside the scale: '
                '${sizes.difference(_allowedFontSizes)}');

        final radii = _matches(source, RegExp(r'circular\(\s*([0-9.]+)'));
        expect(radii.difference(_allowedRadii), isEmpty,
            reason: '$path uses corner radii outside the scale: '
                '${radii.difference(_allowedRadii)}');
      });
    }
  });

  test('the migrated shell no longer reaches for grey by number', () {
    // Colors.white38 / black26 were how three different greys got invented.
    for (final path in _migrated) {
      final source = File(path).readAsStringSync();
      final hits = RegExp(r'Colors\.(white|black)\d\d').allMatches(source);
      expect(hits, isEmpty,
          reason: '$path still names a grey by opacity: '
              '${hits.map((m) => m.group(0)).toSet()}');
    }
  });
}
