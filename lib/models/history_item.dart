class HistoryItem {
  final String id;
  final String url;
  final String title;
  final DateTime visitedAt;

  HistoryItem({
    required this.id,
    required this.url,
    required this.title,
    required this.visitedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'title': title,
        'visitedAt': visitedAt.toIso8601String(),
      };

  factory HistoryItem.fromJson(Map<String, dynamic> json) => HistoryItem(
        id: json['id'] as String? ?? '',
        url: json['url'] as String? ?? '',
        title: json['title'] as String? ?? '未命名网页',
        visitedAt: DateTime.tryParse(json['visitedAt'] as String? ?? '') ?? DateTime.now(),
      );
}
