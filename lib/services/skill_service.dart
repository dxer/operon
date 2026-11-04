import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/skill.dart';
import 'skill_inputs.dart';
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
///
/// Nothing is shipped: a new install starts with an empty library and the user
/// creates their own skills (by describing a task, or recording one).
class SkillService {
  static const String _key = 'pref_skills_v1';

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
      await _instance!._ensureLoaded();
    }
    return _instance!;
  }

  Future<void> _ensureLoaded() async {
    if (_prefs.containsKey(_key)) {
      _skills = _readPrefs();
    } else {
      _skills = await _readPackages();
      await _writePrefsOnly(_skills);
    }
    _loaded = true;
    await _mirrorPackages();
  }

  Future<List<Skill>> _readPackages() async {
    final store = _store;
    if (store == null) return const [];
    final entries = await store.readAll();
    final skills = <Skill>[];
    for (final entry in entries) {
      try {
        skills.add(SkillPackageCodec.decode(entry.files, dirName: entry.dirName));
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

  List<Skill> getSkills() {
    if (!_loaded) return const [];
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
        if (skill.id.trim().isNotEmpty) list.add(SkillInputs.normalize(skill));
      } catch (_) {
        // Ignore a corrupt entry instead of losing the whole library.
      }
    }
    return list;
  }

  Future<void> _save(List<Skill> skills) async {
    final ordered = <Skill>[];
    for (var i = 0; i < skills.length; i++) {
      ordered.add(SkillInputs.normalize(skills[i]).copyWith(sortOrder: i));
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
