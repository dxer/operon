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

  runApp(OperonApp(themeService: themeService));
}

class OperonApp extends StatelessWidget {
  final ThemeService themeService;

  const OperonApp({super.key, required this.themeService});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeService,
      builder: (context, _) {
        return MaterialApp(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          themeMode: themeService.themeMode,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          home: const BrowserPage(),
        );
      },
    );
  }
}
