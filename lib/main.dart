import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'config/app_constants.dart';
import 'config/app_theme.dart';
import 'services/app_version_service.dart';
import 'services/haptic_service.dart';
import 'services/storage_service.dart';
import 'services/theme_service.dart';
import 'views/browser_page.dart';
import 'views/onboarding_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Via-style edge-to-edge canvas: browser content owns the whole screen.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarContrastEnforced: false,
    ),
  );

  // The control layer reaches the page through the WebView DevTools socket,
  // which only exists while WebView debugging is on. It has to stay on in
  // release builds too, or the agent has no way to read or drive a page: the
  // socket is a per-process unix socket that only this app can connect to, and
  // About → Control layer states so. Keep this true, in every build.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(true);
  }

  // Pre-initialize storage & theme service
  final storage = await StorageService.getInstance();
  HapticService.enabled = storage.getHapticsEnabled();
  await AppVersionService.load();
  final themeService = await ThemeService.getInstance();

  // A fresh install has nothing to drive a page with. Existing users already
  // configured a model, so an upgrade must not send them back through setup.
  final showOnboarding =
      !storage.getOnboardingDone() && !storage.getLlmConfig().isValid;

  runApp(
    OperonApp(
      themeService: themeService,
      showOnboarding: showOnboarding,
    ),
  );
}

class OperonApp extends StatefulWidget {
  final ThemeService themeService;

  /// Whether first-run setup should be the first screen.
  final bool showOnboarding;

  const OperonApp({
    super.key,
    required this.themeService,
    this.showOnboarding = false,
  });

  @override
  State<OperonApp> createState() => _OperonAppState();
}

class _OperonAppState extends State<OperonApp> {
  late bool _showOnboarding = widget.showOnboarding;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.themeService,
      builder: (context, _) {
        return MaterialApp(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          themeMode: widget.themeService.themeMode,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          // Setup is a gate, not a page in the browsing history: replacing it
          // in place means back from the browser never lands on onboarding.
          home: _showOnboarding
              ? OnboardingPage(
                  onDone: () => setState(() => _showOnboarding = false),
                )
              : const BrowserPage(),
        );
      },
    );
  }
}
