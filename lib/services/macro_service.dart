import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/agent_action.dart';
import '../models/macro_workflow.dart';
import '../utils/cancellation.dart';
import 'macro_precondition.dart';
import 'webview_controller_wrapper.dart';

class MacroService {
  static const String _keyMacros = 'pref_saved_macros';
  static MacroService? _instance;
  late SharedPreferences _prefs;

  MacroService._();

  static Future<MacroService> getInstance() async {
    if (_instance == null) {
      _instance = MacroService._();
      _instance!._prefs = await SharedPreferences.getInstance();
    }
    return _instance!;
  }

  /// Loads all user saved macros
  List<MacroWorkflow> getMacros() {
    final raw = _prefs.getStringList(_keyMacros) ?? [];
    return raw
        .map((item) {
          try {
            return MacroWorkflow.fromJson(jsonDecode(item));
          } catch (_) {
            return null;
          }
        })
        .whereType<MacroWorkflow>()
        .toList();
  }

  /// Saves a newly recorded macro
  Future<void> saveMacro(MacroWorkflow macro) async {
    final list = getMacros();
    // Replace if exists, else append
    list.removeWhere((m) => m.id == macro.id);
    list.insert(0, macro);

    final raw = list.map((m) => jsonEncode(m.toJson())).toList();
    await _prefs.setStringList(_keyMacros, raw);
  }

  /// Deletes a macro
  Future<void> deleteMacro(String id) async {
    final list = getMacros();
    list.removeWhere((m) => m.id == id);
    final raw = list.map((m) => jsonEncode(m.toJson())).toList();
    await _prefs.setStringList(_keyMacros, raw);
  }

  /// Replays a macro deterministically without invoking any LLM (0 Token Cost!)
  Future<bool> executeMacro({
    required MacroWorkflow macro,
    required WebViewControllerWrapper webView,
    required Function(int currentStep, int totalSteps, String description)
        onProgress,
    CancellationToken? token,
  }) async {
    final currentUrl = await webView.getUrl();
    if (!MacroPrecondition.check(macro: macro, currentUrl: currentUrl).ok) {
      return false;
    }

    for (int i = 0; i < macro.steps.length; i++) {
      if (token?.isCancelled == true) return false;
      final step = macro.steps[i];
      onProgress(i + 1, macro.steps.length, step.description);

      ActionType actionType = ActionType.click;
      switch (step.action) {
        case 'type':
          actionType = ActionType.type;
          break;
        case 'press_key':
        case 'pressKey':
          actionType = ActionType.pressKey;
          break;
        case 'select_option':
        case 'selectOption':
          actionType = ActionType.selectOption;
          break;
        case 'scroll':
          actionType = ActionType.scroll;
          break;
        case 'navigate':
          actionType = ActionType.navigate;
          break;
        case 'hover':
          actionType = ActionType.hover;
          break;
        case 'go_back':
        case 'goBack':
          actionType = ActionType.goBack;
          break;
        default:
          actionType = ActionType.click;
      }

      final action = AgentAction(
        thought: '宏回放: ${step.description}',
        action: actionType,
        text: step.text,
        key: step.key,
        selectValue: step.selectValue,
        direction: step.direction,
        url: step.url,
        rawParams: {
          if (step.selector != null) 'selector': step.selector,
        },
      );

      var result = await webView.executeAction(action);

      if (result['success'] != true) {
        // A failed dispatch means the element was not found/disabled. Retry
        // only idempotent steps: replaying a reply/post/pay step after an
        // uncertain failure could create a duplicate.
        if (step.nonIdempotent) {
          return false;
        }
        await Future.delayed(const Duration(milliseconds: 500));
        if (token?.isCancelled == true) return false;
        result = await webView.executeAction(action);
        if (result['success'] != true) {
          return false;
        }
      }

      if (step.nonIdempotent) {
        // Give the server time to update the UI before the next step.
        await Future.delayed(const Duration(milliseconds: 800));
      }
      await webView.waitForDomStable(timeoutMs: 1800);
      if (token?.isCancelled == true) return false;
    }
    return true;
  }
}
