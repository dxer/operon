import '../protocol/results.dart';

/// Matches outline entries by name or role.
///
/// An agent that has to guess which of eighty similar rows holds the thing it
/// wants will guess wrong; this is the lookup it should use instead. Matching is
/// case-insensitive and substring-based, because a caller rarely knows the exact
/// accessible name, and it never invents a ref: only what the outline showed can
/// be returned.
List<OutlineLine> matchEntries(
  List<OutlineLine> entries, {
  String? query,
  String? role,
  bool exact = false,
  int limit = 20,
}) {
  final needle = (query ?? '').trim().toLowerCase();
  final wantedRole = (role ?? '').trim().toLowerCase();
  final matches = <OutlineLine>[];
  for (final entry in entries) {
    if (wantedRole.isNotEmpty && entry.role.toLowerCase() != wantedRole) {
      continue;
    }
    if (needle.isNotEmpty) {
      final name = entry.name.toLowerCase();
      final label = entry.value?.toLowerCase() ?? '';
      final hit = exact
          ? name == needle || label == needle
          : name.contains(needle) || label.contains(needle);
      if (!hit) continue;
    }
    matches.add(entry);
    if (matches.length >= limit) break;
  }
  return matches;
}
