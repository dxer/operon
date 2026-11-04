import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/skill.dart';
import 'skill_package_codec.dart';

class SkillPackageEntry {
  final String dirName;
  final SkillPackageFiles files;

  const SkillPackageEntry({required this.dirName, required this.files});
}

/// Reads and writes the two-file skill package on disk.
abstract class SkillPackageStore {
  Future<List<SkillPackageEntry>> readAll();

  /// Makes the directory match [skills]: writes changed packages and removes
  /// packages whose skill no longer exists.
  Future<void> sync(List<Skill> skills);
}

/// App-private directory:
/// `<application documents>/operon_skills/<slug>/SKILL.md` + `flow.json`.
class FileSkillPackageStore implements SkillPackageStore {
  final Directory root;

  FileSkillPackageStore(this.root);

  static const String skillFileName = 'SKILL.md';
  static const String flowFileName = 'flow.json';

  /// Names of the directories this store wrote. Pruning is limited to these,
  /// so a package the user dropped in by hand is never deleted.
  static const String manifestFileName = '.operon_manifest.json';

  static Future<FileSkillPackageStore?> open() async {
    // Widget tests run on the host and must never touch the real documents
    // directory. Package-store tests construct the store with a temp dir.
    if (Platform.environment['FLUTTER_TEST'] == 'true') return null;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final root = Directory('${docs.path}/operon_skills');
      if (!await root.exists()) {
        await root.create(recursive: true);
      }
      return FileSkillPackageStore(root);
    } catch (e) {
      // Widget tests have no path_provider channel; prefs remain the cache.
      debugPrint('[Skills] package store unavailable: $e');
      return null;
    }
  }

  @override
  Future<List<SkillPackageEntry>> readAll() async {
    final entries = <SkillPackageEntry>[];
    if (!await root.exists()) return entries;
    try {
      await for (final item in root.list(followLinks: false)) {
        if (item is! Directory) continue;
        final name = item.path.split(Platform.pathSeparator).last;
        if (!_safeName(name)) continue;
        final skillFile = File('${item.path}/$skillFileName');
        if (!await skillFile.exists()) continue;
        try {
          final markdown = await skillFile.readAsString();
          final flowFile = File('${item.path}/$flowFileName');
          final flowJson =
              await flowFile.exists() ? await flowFile.readAsString() : null;
          entries.add(SkillPackageEntry(
            dirName: name,
            files: SkillPackageFiles(
              markdown: markdown,
              flowJson: flowJson,
            ),
          ));
        } catch (e) {
          debugPrint('[Skills] ignoring unreadable package $name: $e');
        }
      }
    } catch (e) {
      debugPrint('[Skills] cannot list package directory: $e');
    }
    return entries;
  }

  @override
  Future<void> sync(List<Skill> skills) async {
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    // Only directories this store wrote may be pruned. A package copied in by
    // hand (or imported from another device) is left alone.
    final owned = await _readManifest();
    final expected = <String>{};
    for (final skill in skills) {
      var dirName = SkillPackageCodec.packageDirName(skill);
      if (!expected.add(dirName)) {
        // Two ids can sanitize to the same slug; keep both packages.
        dirName = '${dirName}_${SkillPackageCodec.stableHash(skill.id)}';
        expected.add(dirName);
      }
      try {
        await _writeOne(skill, dirName);
      } catch (e) {
        debugPrint('[Skills] cannot write package $dirName: $e');
      }
    }

    try {
      await for (final item in root.list(followLinks: false)) {
        if (item is! Directory) continue;
        final name = item.path.split(Platform.pathSeparator).last;
        if (expected.contains(name)) continue;
        if (!owned.contains(name)) continue;
        if (!await File('${item.path}/$skillFileName').exists()) continue;
        await item.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('[Skills] cannot prune packages: $e');
    }

    await _writeManifest(expected);
  }

  Future<Set<String>> _readManifest() async {
    final file = File('${root.path}/$manifestFileName');
    if (!await file.exists()) return <String>{};
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is List) {
        return decoded.map((item) => item.toString()).toSet();
      }
    } catch (_) {
      // A damaged manifest must not block writes; treat it as empty so
      // nothing is pruned this round.
    }
    return <String>{};
  }

  Future<void> _writeManifest(Set<String> dirNames) async {
    try {
      await File('${root.path}/$manifestFileName').writeAsString(
        jsonEncode(dirNames.toList()..sort()),
        flush: true,
      );
    } catch (e) {
      debugPrint('[Skills] cannot write package manifest: $e');
    }
  }

  Future<void> _writeOne(Skill skill, String dirName) async {
    final dir = Directory('${root.path}/$dirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final files = SkillPackageCodec.encode(skill);
    await File('${dir.path}/$skillFileName')
        .writeAsString(files.markdown, flush: true);
    final flowFile = File('${dir.path}/$flowFileName');
    if (files.flowJson == null) {
      if (await flowFile.exists()) await flowFile.delete();
    } else {
      await flowFile.writeAsString(files.flowJson!, flush: true);
    }
  }

  static bool _safeName(String name) {
    return RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(name);
  }
}
