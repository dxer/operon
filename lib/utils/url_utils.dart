/// Shared URL helpers.
///
/// Hosts are compared lowercase and without a leading `www.` so the same site
/// is not treated as two different sites by the agent or skill guard.
String hostOf(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  return normalizeHost(host);
}

String normalizeHost(String host) {
  final lower = host.trim().toLowerCase();
  return lower.startsWith('www.') ? lower.substring(4) : lower;
}

/// Collapses a long host to its registrable domain so compact chips keep the
/// part that identifies the site (`example.co.uk`). The full host belongs in a
/// tooltip, never in the chip itself.
/// Pulls the first `http(s)` link out of text shared into the app.
///
/// Share sheets usually send `标题 https://example.com/...`, and some apps
/// append punctuation right after the link, so trailing sentence marks are
/// trimmed while punctuation that can be part of a URL is kept.
String? extractSharedUrl(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;

  final match = RegExp(
    r'''https?://[^\s<>"']+''',
    caseSensitive: false,
  ).firstMatch(text);
  if (match == null) return null;

  var url = match.group(0)!;
  // Trailing sentence punctuation is never part of the link the sender meant.
  const trailing = '.,;:!?)]}，。；：！？）】」』》';
  while (url.isNotEmpty && trailing.contains(url[url.length - 1])) {
    url = url.substring(0, url.length - 1);
  }

  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return null;
  return url;
}

String compactHost(String host) {
  if (host.length <= 18) return host;
  if (host.contains(':')) return host; // IPv6 literal; never split on dots.
  final labels = host.split('.');
  if (labels.length <= 2 ||
      labels.every((label) => int.tryParse(label) != null)) {
    return host;
  }
  final secondLevel = labels[labels.length - 2];
  final tld = labels.last;
  final keep = tld.length == 2 &&
          const ['co', 'com', 'net', 'org', 'gov', 'edu', 'ac', 'or', 'ne']
              .contains(secondLevel)
      ? 3
      : 2;
  if (labels.length <= keep) return host;
  return labels.sublist(labels.length - keep).join('.');
}
