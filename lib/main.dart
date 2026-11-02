import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'config/app_constants.dart';
import 'config/app_theme.dart';
import 'services/app_version_service.dart';
import 'services/storage_service.dart';
import 'services/theme_service.dart';
import 'views/browser_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Via-style edge-to-edge canvas: browser content owns the whole screen.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Initialize Android WebView platform defaults
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(kDebugMode);
  }

  // Pre-initialize storage & theme service
  await StorageService.getInstance();
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
