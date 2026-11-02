import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/skill_defaults.dart';
import '../models/skill.dart';
import 'quick_command_service.dart';
import 'skill_migration.dart';

/// Persists skills as JSON strings in SharedPreferences.
///
/// On first launch the service migrates `pref_quick_commands` if present, then
/// appends the new flow examples. The legacy key is intentionally left intact
/// for one release so a rollback still finds the old commands.
class SkillService {
  static const String _key = 'pref_skills_v1';
  static const String legacyKey = 'pref_quick_commands';

  static SkillService? _instance;
  late SharedPreferences _prefs;

  SkillService._();

  static Future<SkillService> getInstance() async {
    if (_instance == null) {
      _instance = SkillService._();
      _instance!._prefs = await SharedPreferences.getInstance();
      await _instance!._ensureSeeded();
    }
    return _instance!;
  }

  Future<void> _ensureSeeded() async {
    if (_prefs.containsKey(_key)) return;

    final legacyRaw = _prefs.getStringList(legacyKey);
    final skills = <Skill>[];

    if (legacyRaw != null) {
      final legacy = await QuickCommandService.getInstance();
      for (final command in legacy.getCommands()) {
        if (command.id.trim().isEmpty) continue;
        skills.add(SkillMigration.fromQuickCommand(command));
      }
    } else {
      skills.addAll(SkillDefaults.instructionDefaults());
    }

    final ids = skills.map((skill) => skill.id).toSet();
    for (final flow in SkillDefaults.flowDefaults) {
      if (!ids.contains(flow.id)) {
        skills.add(flow);
        ids.add(flow.id);
      }
    }

    await _save(skills);
  }

  List<Skill> getSkills() {
    final raw = _prefs.getStringList(_key);
    if (raw == null) return SkillDefaults.all();

    final list = <Skill>[];
    for (final entry in raw) {
      try {
        final map = jsonDecode(entry) as Map<String, dynamic>;
        final skill = Skill.fromJson(map);
        if (skill.id.trim().isNotEmpty) list.add(skill);
      } catch (_) {
        // Ignore a corrupt entry instead of losing the whole library.
      }
    }
    list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return list;
  }

  Future<void> saveSkills(List<Skill> skills) async {
    final normalized = <Skill>[];
    for (var i = 0; i < skills.length; i++) {
      normalized.add(skills[i].copyWith(sortOrder: i));
    }
    await _save(normalized);
  }

  Future<void> saveSkill(Skill skill) async {
    final list = getSkills();
    final index = list.indexWhere((item) => item.id == skill.id);
    final now = DateTime.now();
    if (index >= 0) {
      final existing = list[index];
      list[index] = skill.copyWith(
        version: skill.version > existing.version
            ? skill.version
            : existing.version + 1,
        updatedAt: now,
        sortOrder: existing.sortOrder,
      );
    } else {
      list.add(skill.copyWith(
        version: skill.version <= 0 ? 1 : skill.version,
        updatedAt: now,
      ));
    }
    await saveSkills(list);
  }

  Future<void> deleteSkill(String id) async {
    final list = getSkills()..removeWhere((item) => item.id == id);
    await saveSkills(list);
  }

  /// Restores built-in skills while keeping user-created skills.
  Future<void> restoreDefaults() async {
    final defaults = SkillDefaults.all();
    final defaultIds = defaults.map((item) => item.id).toSet();
    final kept = getSkills()
        .where((item) => !item.builtin && !defaultIds.contains(item.id))
        .toList();
    await saveSkills([...defaults, ...kept]);
  }

  Future<void> _save(List<Skill> skills) async {
    final raw = skills.map((item) => jsonEncode(item.toJson())).toList();
    await _prefs.setStringList(_key, raw);
  }

  /// Test helper. Resets the cached singleton between test cases.
  static void resetForTest() {
    _instance = null;
  }
}
