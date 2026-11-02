class UserScript {
  final String id;
  final String name;
  final String description;
  final String
      matchPattern; // e.g. "*://*.zhihu.com/*", "*twitter.com*", or "*"
  final String code;
  final bool isEnabled;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const UserScript({
    required this.id,
    required this.name,
    required this.description,
    required this.matchPattern,
    required this.code,
    this.isEnabled = true,
    required this.createdAt,
    this.updatedAt,
  });

  UserScript copyWith({
    String? id,
    String? name,
    String? description,
    String? matchPattern,
    String? code,
    bool? isEnabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserScript(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      matchPattern: matchPattern ?? this.matchPattern,
      code: code ?? this.code,
      isEnabled: isEnabled ?? this.isEnabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Evaluates whether this script matches the given webpage URL
  bool matchesUrl(String url) {
    if (!isEnabled) return false;
    final pattern = matchPattern.trim().toLowerCase();
    if (pattern.isEmpty ||
        pattern == '*' ||
        pattern == '*://*/*' ||
        pattern == 'all') {
      return true;
    }

    final lowerUrl = url.toLowerCase();

    // Wildcard support: convert wildcard string to regex
    try {
      final regexStr = RegExp.escape(pattern).replaceAll(r'\*', '.*');
      final reg = RegExp('^$regexStr\$', caseSensitive: false);
      if (reg.hasMatch(lowerUrl)) return true;
    } catch (_) {}

    // Fallback: contains match on stripped domains
    final cleanPattern = pattern.replaceAll('*', '').trim();
    if (cleanPattern.isNotEmpty && lowerUrl.contains(cleanPattern)) {
      return true;
    }

    return false;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'matchPattern': matchPattern,
        'code': code,
        'isEnabled': isEnabled,
        'createdAt': createdAt.toIso8601String(),
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      };

  factory UserScript.fromJson(Map<String, dynamic> json) => UserScript(
        id: json['id'] ?? '',
        name: json['name'] ?? '未命名脚本',
        description: json['description'] ?? '',
        matchPattern: json['matchPattern'] ?? '*',
        code: json['code'] ?? '',
        isEnabled: json['isEnabled'] as bool? ?? true,
        createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
        updatedAt: json['updatedAt'] != null
            ? DateTime.tryParse(json['updatedAt'])
            : null,
      );
}
