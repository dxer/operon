/// Lightweight snapshot used to decide whether an action actually changed the
/// page.
///
/// Lengths are used instead of hashes so a same-length ticker/clock update does
/// not look like a change, while text/element growth does.
class PageSignature {
  final String url;
  final String title;
  final int elementCount;
  final int textLength;
  final int scrollHeight;

  const PageSignature({
    required this.url,
    required this.title,
    required this.elementCount,
    required this.textLength,
    required this.scrollHeight,
  });

  factory PageSignature.fromJson(Map<String, dynamic> json) {
    return PageSignature(
      url: json['url']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      elementCount: (json['elementCount'] as num?)?.toInt() ?? 0,
      textLength: (json['textLength'] as num?)?.toInt() ?? 0,
      scrollHeight: (json['scrollHeight'] as num?)?.toInt() ?? 0,
    );
  }

  bool get valid => url.isNotEmpty;

  bool changedFrom(PageSignature other) {
    return url != other.url ||
        title != other.title ||
        elementCount != other.elementCount ||
        textLength != other.textLength ||
        scrollHeight != other.scrollHeight;
  }
}
