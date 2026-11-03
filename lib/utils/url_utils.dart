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
