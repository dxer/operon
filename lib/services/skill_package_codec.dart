import 'dart:convert';

import 'package:yaml/yaml.dart';

import '../config/tool_catalog.dart';
import '../models/skill.dart';
import 'skill_inputs.dart';
import '../utils/url_utils.dart';

/// The two files that make up an Operon skill package.
///
/// `SKILL.md` is the human/model-facing document. `flow.json` exists only for
/// flow skills and contains the executable steps.
class SkillPackageFiles {
  final String markdown;
  final String? flowJson;

  /// Optional package identity used by export/import. It is app state, so it
  /// never appears inside `SKILL.md`.
  final String? id;

  const SkillPackageFiles({
    required this.markdown,
    this.flowJson,
    this.id,
  });
}

class SkillPackageException implements Exception {
  final String message;

  const SkillPackageException(this.message);

  @override
  String toString() => message;
}

/// Converts between [Skill] and the two-file package format.
///
/// The file is intentionally small:
/// - `SKILL.md`: `name`, optional `description` / `hosts` / `inputs` /
///   `policy` / `output`, then the instruction body. No app state (id, origin,
///   builtin, version, sort order) is written.
/// - `flow.json`: `{"schemaVersion":1,"steps":[...]}` for flow skills only.
///   Its presence is what makes a skill a flow; there is no `kind` field.
class SkillPackageCodec {
  SkillPackageCodec._();

  static const int flowSchemaVersion = 1;

  static SkillPackageFiles encode(Skill skill) {
    final hosts = _hostsFor(skill.policy);
    final overrides = _policyOverrides(skill, hosts);
    final front = <String, dynamic>{
      'name': skill.name,
      if (skill.description.trim().isNotEmpty)
        'description': skill.description.trim(),
      if (hosts.isNotEmpty) 'hosts': hosts,
      if (skill.inputs.isNotEmpty)
        'inputs': skill.inputs.map(_encodeInput).toList(),
      if (overrides.isNotEmpty) 'policy': overrides,
      if (skill.output.isNotEmpty) 'output': skill.output,
    };
    final body = skill.kind == SkillKind.instruction
        ? skill.instructions.trim()
        : _flowBody(skill);
    final markdown = '---\n${_yamlEncode(front)}---\n\n$body\n';
    final flowJson = skill.kind == SkillKind.flow
        ? const JsonEncoder.withIndent('  ').convert({
            'schemaVersion': flowSchemaVersion,
            'steps': skill.steps.map((step) => step.toJson()).toList(),
          })
        : null;
    return SkillPackageFiles(
      markdown: '${markdown.trimRight()}\n',
      flowJson: flowJson,
    );
  }

  static Skill decode(SkillPackageFiles files, {String? dirName}) {
    final split = _splitFrontmatter(files.markdown);
    final front = split.front;
    final body = split.body;
    final metadata = _asMap(front['metadata']);

    final name = (front['name']?.toString() ?? '').trim();
    if (name.isEmpty) {
      throw const SkillPackageException('SKILL.md 缺少 name');
    }

    final declaredKind =
        (metadata['operon-kind']?.toString() ?? front['kind']?.toString() ?? '')
            .trim();
    final hasFlow = files.flowJson?.trim().isNotEmpty == true;
    if (declaredKind == 'flow' && !hasFlow) {
      throw const SkillPackageException('流程型技能缺少 flow.json');
    }
    final kind = hasFlow ? SkillKind.flow : SkillKind.instruction;

    final steps = <SkillStep>[];
    if (kind == SkillKind.flow) {
      dynamic decoded;
      try {
        decoded = jsonDecode(files.flowJson!.trim());
      } catch (e) {
        throw SkillPackageException('flow.json 解析失败：$e');
      }
      final rawSteps = decoded is Map ? decoded['steps'] : decoded;
      if (rawSteps is! List) {
        throw const SkillPackageException('flow.json 缺少 steps 数组');
      }
      for (final raw in rawSteps) {
        if (raw is Map) {
          steps.add(SkillStep.fromJson(_asMap(raw)));
        }
      }
      if (steps.isEmpty) {
        throw const SkillPackageException('flow.json 的 steps 为空');
      }
    }

    final rawInputs = front['inputs'] ?? metadata['operon-inputs'];
    final declaredInputs = <SkillInput>[];
    if (rawInputs is List) {
      for (final raw in rawInputs) {
        if (raw is Map) declaredInputs.add(_decodeInput(_asMap(raw)));
      }
    }

    final rawPolicy = front['policy'] ?? metadata['operon-policy'];
    var policy = _baselinePolicyForKind(kind, steps);
    if (rawPolicy is Map) {
      policy = _mergePolicy(policy, _asMap(rawPolicy));
    }
    final hosts = _parseHosts(front['hosts']);
    if (hosts.isNotEmpty) {
      policy = policy.copyWith(
        hostScope: SkillHostScope.list,
        allowedHosts: hosts,
      );
    } else if (policy.hostScope == SkillHostScope.list &&
        policy.allowedHosts.isEmpty) {
      // A list scope without hosts cannot be enforced; treat it as general.
      policy = policy.copyWith(hostScope: SkillHostScope.any);
    }

    final builtin = metadata['operon-builtin'] == true;
    final originName = (metadata['operon-origin']?.toString() ?? '').trim();
    final origin = SkillOrigin.values.firstWhere(
      (item) => item.name == originName,
      orElse: () => builtin ? SkillOrigin.builtin : SkillOrigin.user,
    );
    final title = (metadata['operon-title']?.toString() ?? '').trim();
    final heading = _firstHeading(body);
    // Claude-style packages use a slug in `name` and a human title in the H1.
    // New Operon packages put the human name directly in `name`, so only
    // prefer the H1 when the name actually looks like a slug.
    final looksLikeSlug = RegExp(r'^[a-z0-9_-]+$').hasMatch(name) &&
        (name.contains('-') || name.contains('_'));
    final displayName = title.isNotEmpty
        ? title
        : (_isPlainFrontmatter(front) && heading != null && looksLikeSlug
            ? heading
            : name);
    final oldId = (metadata['operon-id']?.toString() ?? '').trim();
    final dir = (dirName ?? '').trim();
    final id = oldId.isNotEmpty
        ? oldId
        : (dir.isNotEmpty ? dir : idFromName(displayName));
    final updatedAt =
        DateTime.tryParse(metadata['operon-updated-at']?.toString() ?? '');

    final output = _stringMap(front['output'] ?? metadata['operon-output']);

    final skill = Skill(
      id: id,
      name: displayName,
      description: (front['description']?.toString() ?? '').trim(),
      kind: kind,
      origin: origin,
      version: _int(metadata['operon-version'], 1),
      inputs: declaredInputs,
      instructions:
          kind == SkillKind.instruction ? body.trim() : _section(body, '说明'),
      steps: steps,
      output: output,
      policy: policy,
      builtin: builtin,
      sortOrder: _int(metadata['operon-sort-order'], 0),
      updatedAt: updatedAt,
    );
    // Placeholders decide which inputs exist; declarations only decorate them.
    return SkillInputs.normalize(skill);
  }

  /// The directory name is the skill id when it is already filesystem-safe.
  /// Imported or Chinese-only ids get a stable slug/hash instead.
  static String packageDirName(Skill skill) {
    final id = skill.id.trim();
    if (id.isNotEmpty && RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)) {
      return id;
    }
    return _slug(id.isNotEmpty ? id : skill.name, prefix: 'skill');
  }

  static String idFromName(String name) {
    return _slug(name, prefix: 'skill');
  }

  static String _slug(String source, {required String prefix}) {
    final slug = source
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (slug.isEmpty) return '${prefix}_${_stableHash(source)}';
    return slug.startsWith('${prefix}_') ? slug : '${prefix}_$slug';
  }

  /// Stable short hash used to disambiguate filesystem names.
  static String stableHash(String value) => _stableHash(value);

  static String _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static List<String> _hostsFor(SkillPolicy policy) {
    if (policy.hostScope == SkillHostScope.any) return const [];
    final seen = <String>{};
    final hosts = <String>[];
    for (final raw in policy.allowedHosts) {
      final host = _normalizeHost(raw);
      if (host.isEmpty || !seen.add(host)) continue;
      hosts.add(host);
    }
    return hosts;
  }

  static Map<String, dynamic> _policyOverrides(
    Skill skill,
    List<String> hosts,
  ) {
    final policy = skill.policy;
    final base = _baselinePolicy(skill);
    final overrides = <String, dynamic>{};
    if (policy.maxSteps != base.maxSteps) {
      overrides['max_steps'] = policy.maxSteps;
    }
    if (policy.maxSideEffects != base.maxSideEffects) {
      overrides['max_side_effects'] = policy.maxSideEffects;
    }
    if (policy.maxDurationMs != base.maxDurationMs) {
      overrides['max_duration_ms'] = policy.maxDurationMs;
    }
    if (policy.maxItems != base.maxItems) {
      overrides['max_items'] = policy.maxItems;
    }
    if (policy.pacingMs != base.pacingMs) {
      overrides['pacing_ms'] = policy.pacingMs;
    }
    if (policy.uniqueTarget != base.uniqueTarget) {
      overrides['unique_target'] = policy.uniqueTarget;
    }
    if (policy.uniqueContent != base.uniqueContent) {
      overrides['unique_content'] = policy.uniqueContent;
    }
    if (policy.confirmWrites != true) {
      overrides['confirm_writes'] = policy.confirmWrites;
    }
    if (policy.confirmDestructive != true) {
      overrides['confirm_destructive'] = policy.confirmDestructive;
    }
    if (policy.stopOn.join('|') != base.stopOn.join('|')) {
      overrides['stop_on'] = policy.stopOn;
    }
    if (hosts.isEmpty && policy.hostScope == SkillHostScope.currentHost) {
      overrides['host_scope'] = 'currentHost';
    }
    return overrides;
  }

  static SkillPolicy _baselinePolicy(Skill skill) {
    return _baselinePolicyForKind(skill.kind, skill.steps);
  }

  static SkillPolicy _baselinePolicyForKind(
    SkillKind kind,
    List<SkillStep> steps,
  ) {
    if (kind == SkillKind.instruction) return const SkillPolicy();
    final writeCount = steps.where((step) {
      return ToolCatalog.find(step.tool)?.isWrite == true;
    }).length;
    return SkillPolicy(
      maxSteps: steps.length + 4,
      maxSideEffects: writeCount,
      maxItems: 1,
      maxDurationMs: 300000,
    );
  }

  static Map<String, dynamic> _encodeInput(SkillInput input) {
    final hint = input.hint?.trim() ?? '';
    return {
      'key': input.key,
      'label': input.label,
      if (input.type != SkillInputType.text) 'type': input.type.name,
      if (input.required) 'required': true,
      if (input.defaultValue.trim().isNotEmpty) 'default': input.defaultValue,
      if (input.options.isNotEmpty) 'options': input.options,
      if (hint.isNotEmpty) 'hint': hint,
      if (input.maxLength != null) 'max_length': input.maxLength,
    };
  }

  static SkillInput _decodeInput(Map<String, dynamic> raw) {
    final typeName = (raw['type']?.toString() ?? '').trim();
    final type = SkillInputType.values.firstWhere(
      (item) => item.name == typeName,
      orElse: () => SkillInputType.text,
    );
    final rawOptions = raw['options'];
    final options = rawOptions is List
        ? rawOptions.map((item) => item.toString()).toList()
        : const <String>[];
    final rawMax = raw['max_length'] ?? raw['maxLength'];
    final maxLength =
        rawMax is num ? rawMax.toInt() : int.tryParse(rawMax?.toString() ?? '');
    final hint = (raw['hint']?.toString() ?? '').trim();
    return SkillInput(
      key: (raw['key']?.toString() ?? '').trim(),
      label: (raw['label']?.toString() ?? '').trim(),
      type: type,
      defaultValue: (raw['default'] ?? raw['defaultValue'])?.toString() ?? '',
      options: options,
      required: _bool(raw['required'], false),
      hint: hint.isEmpty ? null : hint,
      maxLength: maxLength,
    );
  }

  static SkillPolicy _mergePolicy(
    SkillPolicy base,
    Map<String, dynamic> raw,
  ) {
    final scopeName =
        (raw['host_scope'] ?? raw['hostScope'])?.toString().trim() ?? '';
    final scope = SkillHostScope.values.firstWhere(
      (item) => item.name == scopeName,
      orElse: () => base.hostScope,
    );
    final rawHosts = raw['allowed_hosts'] ?? raw['allowedHosts'];
    final rawStopOn = raw['stop_on'] ?? raw['stopOn'];
    return SkillPolicy(
      maxSteps: _int(raw['max_steps'] ?? raw['maxSteps'], base.maxSteps),
      maxSideEffects: _int(
        raw['max_side_effects'] ?? raw['maxSideEffects'],
        base.maxSideEffects,
      ),
      maxItems: _int(raw['max_items'] ?? raw['maxItems'], base.maxItems),
      maxDurationMs: _int(
        raw['max_duration_ms'] ?? raw['maxDurationMs'],
        base.maxDurationMs,
      ),
      pacingMs: _int(raw['pacing_ms'] ?? raw['pacingMs'], base.pacingMs),
      uniqueTarget:
          _bool(raw['unique_target'] ?? raw['uniqueTarget'], base.uniqueTarget),
      uniqueContent: _bool(
        raw['unique_content'] ?? raw['uniqueContent'],
        base.uniqueContent,
      ),
      confirmWrites: _bool(
          raw['confirm_writes'] ?? raw['confirmWrites'], base.confirmWrites),
      confirmDestructive: _bool(
        raw['confirm_destructive'] ?? raw['confirmDestructive'],
        base.confirmDestructive,
      ),
      stopOn: rawStopOn is List
          ? rawStopOn.map((item) => item.toString()).toList()
          : base.stopOn,
      hostScope: scope,
      allowedHosts: rawHosts is List
          ? rawHosts.map((item) => item.toString()).toList()
          : base.allowedHosts,
    );
  }

  static List<String> _parseHosts(dynamic raw) {
    final values = <String>[];
    if (raw is List) {
      values.addAll(raw.map((item) => item.toString()));
    } else if (raw is String) {
      values.addAll(raw.split(RegExp(r'[,，\s]+')));
    }
    final seen = <String>{};
    final hosts = <String>[];
    for (final value in values) {
      final host = _normalizeHost(value);
      if (host.isEmpty || !seen.add(host)) continue;
      hosts.add(host);
    }
    return hosts;
  }

  static String _normalizeHost(String value) => normalizeHostInput(value);

  static bool _isPlainFrontmatter(Map<String, dynamic> front) {
    return front.keys.every((key) => key == 'name' || key == 'description');
  }

  static String _flowBody(Skill skill) {
    final buffer = StringBuffer()..writeln('# ${skill.name}');
    final description = skill.description.trim();
    if (description.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(description);
    }
    if (skill.steps.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## 步骤');
      for (var i = 0; i < skill.steps.length; i++) {
        final step = skill.steps[i];
        buffer.writeln('${i + 1}. **${step.name}** — `${step.tool}`');
      }
    }
    final notes = skill.instructions.trim();
    if (notes.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## 说明')
        ..writeln(notes);
    }
    return buffer.toString().trimRight();
  }

  static _Frontmatter _splitFrontmatter(String source) {
    final normalized = source.replaceFirst('﻿', '').replaceAll('\r\n', '\n');
    final match = RegExp(
      r'^---[ \t]*\n([\s\S]*?)\n---[ \t]*(?:\n|$)',
    ).firstMatch(normalized);
    if (match == null) {
      throw const SkillPackageException('SKILL.md 缺少 --- frontmatter');
    }
    dynamic loaded;
    try {
      loaded = loadYaml(match.group(1) ?? '');
    } catch (e) {
      throw SkillPackageException('frontmatter 解析失败：$e');
    }
    if (loaded is! YamlMap) {
      throw const SkillPackageException('frontmatter 必须是 YAML 对象');
    }
    return _Frontmatter(
      front: _asMap(_toDart(loaded)),
      body: normalized.substring(match.end),
    );
  }

  static String? _firstHeading(String body) {
    final match = RegExp(r'^#\s+(.+)$', multiLine: true).firstMatch(body);
    final value = match?.group(1)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  /// Reads one `## heading` section, used to round-trip generated notes.
  static String _section(String body, String heading) {
    final start = RegExp(
      '^##\\s+${RegExp.escape(heading)}\\s*\$',
      multiLine: true,
    ).firstMatch(body);
    if (start == null) return '';
    final rest = body.substring(start.end);
    final next = RegExp(r'^##\s+', multiLine: true).firstMatch(rest);
    return (next == null ? rest : rest.substring(0, next.start)).trim();
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return value.map(
        (key, item) => MapEntry(key.toString(), _toDart(item)),
      );
    }
    return const {};
  }

  static Map<String, String> _stringMap(dynamic value) {
    if (value is Map) {
      return value.map(
        (key, item) => MapEntry(key.toString(), item?.toString() ?? ''),
      );
    }
    return const {};
  }

  static dynamic _toDart(dynamic value) {
    if (value is YamlMap) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): _toDart(entry.value),
      };
    }
    if (value is YamlList) {
      return value.map(_toDart).toList();
    }
    return value;
  }

  static int _int(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static bool _bool(dynamic value, bool fallback) {
    if (value is bool) return value;
    if (value is String) {
      final lower = value.trim().toLowerCase();
      if (lower == 'true') return true;
      if (lower == 'false') return false;
    }
    return fallback;
  }

  static String _yamlEncode(Map<String, dynamic> map) {
    final buffer = StringBuffer();
    _writeMap(buffer, map, 0);
    return buffer.toString();
  }

  static void _writeMap(
    StringBuffer buffer,
    Map<dynamic, dynamic> map,
    int indent,
  ) {
    for (final entry in map.entries) {
      final key = _yamlKey(entry.key.toString());
      final value = entry.value;
      if (_isBlock(value)) {
        buffer.writeln('${' ' * indent}$key:');
        _writeNode(buffer, value, indent + 2);
      } else {
        buffer.writeln('${' ' * indent}$key: ${_yamlScalar(value)}');
      }
    }
  }

  static void _writeNode(StringBuffer buffer, Object value, int indent) {
    if (value is Map) {
      _writeMap(buffer, value, indent);
      return;
    }
    if (value is List) {
      for (final item in value) {
        if (item is Map && item.isNotEmpty) {
          // Put the first key on the `-` line so lists of mappings stay
          // readable:
          //   inputs:
          //     - key: "content"
          //       label: "内容"
          final entries = item.entries.toList();
          final first = entries.first;
          final firstKey = _yamlKey(first.key.toString());
          final firstValue = first.value;
          if (_isBlock(firstValue)) {
            buffer.writeln('${' ' * indent}- $firstKey:');
            _writeNode(buffer, firstValue, indent + 4);
          } else {
            buffer.writeln(
              '${' ' * indent}- $firstKey: ${_yamlScalar(firstValue)}',
            );
          }
          if (entries.length > 1) {
            _writeMap(
              buffer,
              Map.fromEntries(entries.skip(1)),
              indent + 2,
            );
          }
        } else if (_isBlock(item)) {
          buffer.writeln('${' ' * indent}-');
          _writeNode(buffer, item, indent + 2);
        } else {
          buffer.writeln('${' ' * indent}- ${_yamlScalar(item)}');
        }
      }
    }
  }

  static bool _isBlock(Object? value) {
    return (value is Map && value.isNotEmpty) ||
        (value is List && value.isNotEmpty);
  }

  static String _yamlScalar(Object? value) {
    if (value == null) return 'null';
    if (value is bool || value is num) return '$value';
    if (value is Map) return '{}';
    if (value is List) return '[]';
    return jsonEncode(value.toString());
  }

  static String _yamlKey(String key) {
    return RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(key) ? key : jsonEncode(key);
  }
}

class _Frontmatter {
  final Map<String, dynamic> front;
  final String body;

  const _Frontmatter({required this.front, required this.body});
}
