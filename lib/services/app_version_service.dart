import 'package:package_info_plus/package_info_plus.dart';

/// Single source of truth for the app version.
///
/// The only value developers edit is `version:` in pubspec.yaml. At runtime
/// this service reads the version baked into the installed APK, so the
/// settings/about screens can never drift from the actual build.
class AppVersionService {
  static String _version = '0.0.0';
  static String _buildNumber = '0';
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    try {
      final info = await PackageInfo.fromPlatform();
      _version = info.version.isEmpty ? '0.0.0' : info.version;
      _buildNumber = info.buildNumber.isEmpty ? '0' : info.buildNumber;
    } catch (_) {
      _version = '0.0.0';
      _buildNumber = '0';
    }
    _loaded = true;
  }

  /// e.g. `0.4.0`
  static String get version => _version;

  /// e.g. `4`
  static String get buildNumber => _buildNumber;

  /// e.g. `v0.4.0`
  static String get shortLabel => 'v$_version';

  /// e.g. `v0.4.0 (构建 0.4.0+4)`
  static String get fullLabel => 'v$_version (构建 $_version+$_buildNumber)';
}
