class BookmarkItem {
  final String id;
  final String url;
  final String title;
  final DateTime createdAt;

  BookmarkItem({
    required this.id,
    required this.url,
    required this.title,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
      };

  factory BookmarkItem.fromJson(Map<String, dynamic> json) => BookmarkItem(
        id: json['id'] as String? ?? '',
        url: json['url'] as String? ?? '',
        title: json['title'] as String? ?? '书签',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      );
}
