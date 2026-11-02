import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/quick_command_defaults.dart';
import '../models/quick_command.dart';

/// Persists quick commands as JSON strings in SharedPreferences.
///
/// The first launch seeds the built-in examples. After that the stored list is
/// authoritative, so editing or deleting a built-in command is permanent until
/// the user chooses "restore defaults".
class QuickCommandService {
  static const String _key = 'pref_quick_commands';
  static QuickCommandService? _instance;
  late SharedPreferences _prefs;

  QuickCommandService._();

  static Future<QuickCommandService> getInstance() async {
    if (_instance == null) {
      _instance = QuickCommandService._();
      _instance!._prefs = await SharedPreferences.getInstance();
    }
    return _instance!;
  }

  List<QuickCommand> getCommands() {
    final raw = _prefs.getStringList(_key);
    if (raw == null) {
      final defaults = QuickCommandDefaults.all();
      unawaited(_save(defaults));
      return defaults;
    }
    final list = <QuickCommand>[];
    for (final entry in raw) {
      try {
        final map = jsonDecode(entry) as Map<String, dynamic>;
        final command = QuickCommand.fromJson(map);
        if (command.id.isNotEmpty) list.add(command);
      } catch (_) {
        // Ignore corrupt entries instead of losing the whole list.
      }
    }
    list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return list;
  }

  Future<void> saveCommands(List<QuickCommand> commands) async {
    final normalized = <QuickCommand>[];
    for (var i = 0; i < commands.length; i++) {
      normalized.add(commands[i].copyWith(sortOrder: i));
    }
    await _save(normalized);
  }

  Future<void> saveCommand(QuickCommand command) async {
    final list = getCommands();
    final index = list.indexWhere((item) => item.id == command.id);
    if (index >= 0) {
      list[index] = command;
    } else {
      list.add(command);
    }
    await saveCommands(list);
  }

  Future<void> deleteCommand(String id) async {
    final list = getCommands()..removeWhere((item) => item.id == id);
    await saveCommands(list);
  }

  Future<void> restoreDefaults() async {
    await saveCommands(QuickCommandDefaults.all());
  }

  Future<void> _save(List<QuickCommand> commands) async {
    final raw = commands.map((item) => jsonEncode(item.toJson())).toList();
    await _prefs.setStringList(_key, raw);
  }

  /// Test helper. Resets the cached singleton between test cases.
  static void resetForTest() {
    _instance = null;
  }
}
