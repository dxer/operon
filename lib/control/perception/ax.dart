/// The accessibility nodes `Accessibility.getFullAXTree` returns, parsed.
///
/// The accessibility tree is the right source for an agent: it is what the
/// browser itself computes for assistive technology, so it already knows which
/// nodes are controls, what they are called, whether they are disabled, checked
/// or expanded, and what value a field holds. Rebuilding that from CSS selectors
/// and `innerText` is what the old layer did, and it lost every one of those
/// facts.
class AxNode {
  const AxNode({
    required this.nodeId,
    required this.role,
    this.parentId,
    this.childIds = const [],
    this.name = '',
    this.value,
    this.ignored = false,
    this.backendNodeId,
    this.properties = const {},
    this.sessionId,
  });

  final String nodeId;
  final String? parentId;
  final List<String> childIds;
  final String role;
  final String name;
  final String? value;
  final bool ignored;
  final int? backendNodeId;
  final Map<String, Object?> properties;

  /// Which frame session produced this node; null for the main frame.
  final String? sessionId;

  bool get isInteractive => interactiveRoles.contains(role);

  /// True for a boolean accessibility property such as `disabled`.
  bool flag(String name) {
    final raw = properties[name];
    if (raw is bool) return raw;
    return raw == 'true';
  }

  bool? optionalFlag(String name) {
    if (!properties.containsKey(name)) return null;
    return flag(name);
  }

  @override
  String toString() => 'AxNode($role, name: $name, ref: $backendNodeId)';
}

/// Roles an action can address.
const Set<String> interactiveRoles = {
  'button',
  'link',
  'textbox',
  'searchbox',
  'checkbox',
  'radio',
  'combobox',
  'listbox',
  'option',
  'menuitem',
  'menuitemcheckbox',
  'menuitemradio',
  'slider',
  'spinbutton',
  'switch',
  'tab',
  'treeitem',
  'Iframe',
  'DisclosureTriangle',
};

/// Roles that accept typed text.
const Set<String> editableRoles = {
  'textbox',
  'searchbox',
  'combobox',
  'spinbutton',
};

/// Wrappers that carry no meaning of their own: they are printed only when
/// they have a name, otherwise the walk passes straight through them.
const Set<String> structuralRoles = {
  'generic',
  'none',
  'presentation',
  'group',
  'LabelText',
  'Legend',
  'rowgroup',
  'row',
  'cell',
  'gridcell',
  'listitem',
  'list',
  'table',
  'grid',
  'RootWebArea',
  'WebArea',
  'document',
  'main',
  'region',
  'article',
  'navigation',
  'banner',
  'contentinfo',
  'complementary',
  'form',
  'menu',
  'menubar',
  'toolbar',
  'tabpanel',
  'tablist',
  'application',
  'scrollbar',
  'strong',
  'emphasis',
  'code',
  'LineBreak',
  'InlineTextBox',
};

/// Roles whose text is page content worth reading rather than acting on.
const Set<String> contentRoles = {
  'heading',
  'paragraph',
  'StaticText',
  'DescriptionList',
  'DescriptionListTerm',
  'DescriptionListDetail',
  'blockquote',
  'caption',
  'alert',
  'status',
};

/// Parses the `nodes` array of an `Accessibility.getFullAXTree` result.
List<AxNode> parseAxNodes(Object? raw) {
  if (raw is! List) return const [];
  final nodes = <AxNode>[];
  for (final entry in raw) {
    if (entry is! Map<String, Object?>) continue;
    final nodeId = entry['nodeId'] as String?;
    if (nodeId == null) continue;
    final role = _valueOf(entry['role']) ?? '';
    nodes.add(AxNode(
      nodeId: nodeId,
      role: role,
      parentId: entry['parentId'] as String?,
      childIds:
          (entry['childIds'] as List?)?.whereType<String>().toList(growable: false) ?? const [],
      name: _valueOf(entry['name']) ?? '',
      value: _valueOf(entry['value']),
      ignored: entry['ignored'] == true,
      backendNodeId: (entry['backendDOMNodeId'] as num?)?.toInt(),
      properties: _propertiesOf(entry['properties']),
    ));
  }
  return nodes;
}

String? _valueOf(Object? raw) {
  if (raw == null) return null;
  if (raw is String) return raw;
  if (raw is Map) {
    final value = raw['value'];
    if (value == null) return null;
    if (value is bool) return value ? 'true' : 'false';
    return '$value';
  }
  return '$raw';
}

Map<String, Object?> _propertiesOf(Object? raw) {
  if (raw is! List) return const {};
  final properties = <String, Object?>{};
  for (final entry in raw) {
    if (entry is! Map) continue;
    final name = entry['name'];
    if (name is! String) continue;
    final value = entry['value'];
    properties[name] = value is Map ? value['value'] : value;
  }
  return properties;
}
