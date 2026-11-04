import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/skill_defaults.dart';
import '../models/skill.dart';
import 'quick_command_service.dart';
import 'skill_migration.dart';
import 'skill_package_codec.dart';
import 'skill_package_store.dart';
import 'skill_validator.dart';

/// Persists skills in two places:
/// - `SharedPreferences` is the fast index/cache used by the synchronous UI.
/// - `operon_skills/<slug>/SKILL.md` + `flow.json` is the portable package.
///
/// On a fresh install with no prefs, existing package files are imported back
/// into the cache. Otherwise prefs stay authoritative and packages are a
/// mirror, so a failed file write can never lose the user's library.
class SkillService {
  static const String _key = 'pref_skills_v1';
  static const String legacyKey = 'pref_quick_commands';

  static SkillService? _instance;
  late SharedPreferences _prefs;
  SkillPackageStore? _store;
  List<Skill> _skills = const [];
  bool _loaded = false;

  /// Test hook: inject a package store backed by a temporary directory.
  static SkillPackageStore? debugPackageStore;

  SkillService._();

  static Future<SkillService> getInstance() async {
    if (_instance == null) {
      _instance = SkillService._();
      _instance!._prefs = await SharedPreferences.getInstance();
      _instance!._store =
          debugPackageStore ?? await FileSkillPackageStore.open();
      await _instance!._ensureSeeded();
    }
    return _instance!;
  }

  Future<void> _ensureSeeded() async {
    if (_prefs.containsKey(_key)) {
      _skills = _readPrefs();
    } else {
      final fromPackages = await _readPackages();
      if (fromPackages.isNotEmpty) {
        _skills = fromPackages;
        await _writePrefsOnly(_skills);
      } else {
        _skills = await _seedDefaults();
      }
    }
    _loaded = true;

    await _upgradeBuiltins();
    if (!_prefs.containsKey(_key)) {
      await _save(_skills);
    } else {
      await _mirrorPackages();
    }
  }

  /// Seeds the library from legacy quick commands or the shipped defaults.
  Future<List<Skill>> _seedDefaults() async {
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
        skills.add(SkillDefaults.withRevision(flow));
        ids.add(flow.id);
      }
    }
    return skills;
  }

  Future<List<Skill>> _readPackages() async {
    final store = _store;
    if (store == null) return const [];
    final entries = await store.readAll();
    final shipped = {
      for (final skill in SkillDefaults.all()) skill.id: skill,
    };
    final skills = <Skill>[];
    for (final entry in entries) {
      try {
        var decoded = SkillPackageCodec.decode(
          entry.files,
          dirName: entry.dirName,
        );
        // App state is not written to SKILL.md. On a fresh prefs store we can
        // still recognize shipped skills by id, so built-in upgrades work.
        final builtin = shipped[decoded.id];
        if (builtin != null) {
          decoded = decoded.copyWith(
            builtin: true,
            origin: SkillOrigin.builtin,
            sortOrder: builtin.sortOrder,
            // `output` is app-side result mapping, not portable skill content.
            output: decoded.output.isEmpty ? builtin.output : decoded.output,
          );
        }
        skills.add(decoded);
      } catch (e) {
        debugPrint('[Skills] ignoring package ${entry.dirName}: $e');
      }
    }
    skills.sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
    });
    return skills;
  }

  /// Applies shipped content changes to built-in skills the user never edited.
  ///
  /// A version at or above the shipped revision means the stored copy was
  /// edited (or is already current), so it is left untouched.
  Future<void> _upgradeBuiltins() async {
    final shipped = {for (final skill in SkillDefaults.all()) skill.id: skill};
    var changed = false;
    for (var i = 0; i < _skills.length; i++) {
      final stored = _skills[i];
      final latest = shipped[stored.id];
      if (latest == null || !stored.builtin) continue;
      if (stored.version >= latest.version) continue;
      _skills[i] = latest.copyWith(sortOrder: stored.sortOrder);
      changed = true;
    }
    if (changed) {
      await _save(_skills);
    }
  }

  List<Skill> getSkills() {
    if (!_loaded) return SkillDefaults.all();
    return List<Skill>.from(_skills);
  }

  Future<void> saveSkills(List<Skill> skills) async {
    await _save(skills);
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

  /// Encodes every skill as the two-file package format, tagged with its id so
  /// an import can restore the same identity instead of deriving a new one.
  List<SkillPackageFiles> exportPackages() {
    return getSkills().map((skill) {
      final files = SkillPackageCodec.encode(skill);
      return SkillPackageFiles(
        markdown: files.markdown,
        flowJson: files.flowJson,
        id: skill.id,
      );
    }).toList();
  }

  /// Imports decoded packages. Returns one human-readable error per rejected
  /// package; valid packages are saved even when another one fails.
  Future<List<String>> importPackages(List<SkillPackageFiles> packages) async {
    final errors = <String>[];
    final imported = <Skill>[];
    final validator = SkillValidator();
    for (final files in packages) {
      try {
        final skill = SkillPackageCodec.decode(files, dirName: files.id);
        final validation = validator.validate(skill);
        if (validation.hasErrors) {
          errors.add('${skill.name}: ${validation.errors.first.message}');
          continue;
        }
        imported.add(skill);
      } catch (e) {
        errors.add(e.toString());
      }
    }
    for (final skill in imported) {
      await saveSkill(skill);
    }
    return errors;
  }

  List<Skill> _readPrefs() {
    final raw = _prefs.getStringList(_key);
    if (raw == null) return const [];
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
    return list;
  }

  Future<void> _save(List<Skill> skills) async {
    final ordered = <Skill>[];
    for (var i = 0; i < skills.length; i++) {
      ordered.add(skills[i].copyWith(sortOrder: i));
    }
    _skills = List<Skill>.unmodifiable(ordered);
    _loaded = true;
    await _writePrefsOnly(_skills);
    await _mirrorPackages();
  }

  Future<void> _writePrefsOnly(List<Skill> skills) async {
    final raw = skills.map((item) => jsonEncode(item.toJson())).toList();
    await _prefs.setStringList(_key, raw);
  }

  Future<void> _mirrorPackages() async {
    final store = _store;
    if (store == null) return;
    try {
      await store.sync(_skills);
    } catch (e) {
      debugPrint('[Skills] cannot mirror packages: $e');
    }
  }

  /// Test helper. Resets the cached singleton between test cases.
  static void resetForTest() {
    _instance = null;
    debugPackageStore = null;
  }
}
