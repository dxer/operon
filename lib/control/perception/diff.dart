/// Line diffs between two snapshots.
///
/// The caller's next decision depends on "what changed", which no amount of
/// re-sending the whole page answers. The diff is deliberately coarse: it
/// compares rendered lines, so a renamed button or a new row shows up, while
/// re-ordering noise stays cheap.
List<String> diffLines(
  List<String> before,
  List<String> after, {
  int max = 40,
}) {
  if (before.isEmpty && after.isEmpty) return const [];
  if (before.length * after.length > 250000) {
    return _setDiff(before, after, max);
  }
  return _lcsDiff(before, after, max);
}

/// Beyond a few hundred lines the LCS table is not worth its memory, and the
/// answer a person needs is the same: what appeared, what went away.
List<String> _setDiff(List<String> before, List<String> after, int max) {
  final remaining = <String, int>{};
  for (final line in before) {
    remaining.update(line, (count) => count + 1, ifAbsent: () => 1);
  }
  final changes = <String>[];
  for (final line in after) {
    final count = remaining[line];
    if (count == null || count == 0) {
      changes.add('+ $line');
      if (changes.length >= max) return changes;
    } else {
      remaining[line] = count - 1;
    }
  }
  for (final line in before) {
    final count = remaining[line];
    if (count != null && count > 0) {
      changes.add('- $line');
      remaining[line] = count - 1;
      if (changes.length >= max) return changes;
    }
  }
  return changes;
}

List<String> _lcsDiff(List<String> before, List<String> after, int max) {
  final n = before.length;
  final m = after.length;
  final table = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      table[i][j] = before[i] == after[j]
          ? table[i + 1][j + 1] + 1
          : (table[i + 1][j] >= table[i][j + 1] ? table[i + 1][j] : table[i][j + 1]);
    }
  }
  final changes = <String>[];
  var i = 0;
  var j = 0;
  while (i < n && j < m) {
    if (before[i] == after[j]) {
      i++;
      j++;
    } else if (table[i + 1][j] >= table[i][j + 1]) {
      changes.add('- ${before[i]}');
      i++;
      if (changes.length >= max) return changes;
    } else {
      changes.add('+ ${after[j]}');
      j++;
      if (changes.length >= max) return changes;
    }
  }
  while (i < n && changes.length < max) {
    changes.add('- ${before[i]}');
    i++;
  }
  while (j < m && changes.length < max) {
    changes.add('+ ${after[j]}');
    j++;
  }
  return changes;
}
