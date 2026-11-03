import 'dart:convert';

/// Merges a newly extracted payload into everything gathered so far.
///
/// The agent reports data incrementally ("the next page has 20 more items") and
/// the old code replaced the accumulated value with each report, silently
/// dropping the previous page. Lists are concatenated with exact duplicates
/// removed; maps are merged key by key, list values included.
dynamic mergeExtractedData(
  dynamic previous,
  dynamic incoming, {
  int maxItems = 500,
}) {
  if (incoming == null) return previous;
  if (previous == null) return _cap(incoming, maxItems);

  if (previous is List && incoming is List) {
    return _cap(_dedupe([...previous, ...incoming]), maxItems);
  }

  if (previous is Map && incoming is Map) {
    final merged = <String, dynamic>{};
    previous.forEach((key, value) => merged['$key'] = value);
    incoming.forEach((key, value) {
      final existing = merged['$key'];
      merged['$key'] = existing is List && value is List
          ? _cap(_dedupe([...existing, ...value]), maxItems)
          : value;
    });
    return merged;
  }

  // Different shapes: the newest answer wins, since it is what the model
  // currently wants to report.
  return _cap(incoming, maxItems);
}

List<dynamic> _dedupe(List<dynamic> items) {
  final seen = <String>{};
  final output = <dynamic>[];
  for (final item in items) {
    String key;
    try {
      key = jsonEncode(item);
    } catch (_) {
      key = item.toString();
    }
    if (seen.add(key)) output.add(item);
  }
  return output;
}

dynamic _cap(dynamic value, int maxItems) {
  if (value is List && value.length > maxItems) {
    return value.sublist(0, maxItems);
  }
  return value;
}
