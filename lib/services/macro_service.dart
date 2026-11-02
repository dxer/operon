import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/agent_action.dart';
import '../models/macro_workflow.dart';
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
  }) async {
    for (int i = 0; i < macro.steps.length; i++) {
      final step = macro.steps[i];
      onProgress(i + 1, macro.steps.length, step.description);

      ActionType actionType = ActionType.click;
      if (step.action == 'type') actionType = ActionType.type;
      if (step.action == 'press_key' || step.action == 'pressKey') {
        actionType = ActionType.pressKey;
      }
      if (step.action == 'select_option' || step.action == 'selectOption') {
        actionType = ActionType.selectOption;
      }
      if (step.action == 'scroll') actionType = ActionType.scroll;

      final action = AgentAction(
        thought: '宏回放: ${step.description}',
        action: actionType,
        text: step.text,
        key: step.key,
        direction: step.direction,
        rawParams: {
          if (step.selector != null) 'selector': step.selector,
        },
      );

      final result = await webView.executeAction(action);
      if (result['success'] == false) {
        // Retry slightly with wait
        await Future.delayed(const Duration(milliseconds: 500));
        await webView.executeAction(action);
      }

      await webView.waitForDomStable(timeoutMs: 1800);
    }
    return true;
  }
}
