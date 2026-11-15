enum DownloadStatus {
  downloading,
  completed,
  failed,
  cancelled,
}

class DownloadItem {
  const DownloadItem({
    required this.id,
    required this.url,
    required this.filename,
    this.filePath,
    this.mimeType,
    this.receivedBytes = 0,
    this.totalBytes = -1,
    this.status = DownloadStatus.downloading,
    this.error,
    required this.createdAt,
  });

  final String id;
  final String url;
  final String filename;
  final String? filePath;
  final String? mimeType;
  final int receivedBytes;
  final int totalBytes;
  final DownloadStatus status;
  final String? error;
  final DateTime createdAt;

  double? get progress {
    if (status == DownloadStatus.completed) return 1.0;
    if (totalBytes <= 0) return null;
    return (receivedBytes / totalBytes).clamp(0.0, 1.0);
  }

  String get statusLabel => switch (status) {
        DownloadStatus.downloading => totalBytes > 0
            ? '下载中 · ${formatBytes(receivedBytes)} / ${formatBytes(totalBytes)}'
            : '下载中 · ${formatBytes(receivedBytes)}',
        DownloadStatus.completed =>
            '已完成 · ${formatBytes(totalBytes > 0 ? totalBytes : receivedBytes)}',
        DownloadStatus.failed => error?.isNotEmpty == true ? '失败：$error' : '下载失败',
        DownloadStatus.cancelled => '已取消',
      };

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }

  DownloadItem copyWith({
    String? filename,
    String? filePath,
    String? mimeType,
    int? receivedBytes,
    int? totalBytes,
    DownloadStatus? status,
    String? error,
    bool clearError = false,
  }) =>
      DownloadItem(
        id: id,
        url: url,
        filename: filename ?? this.filename,
        filePath: filePath ?? this.filePath,
        mimeType: mimeType ?? this.mimeType,
        receivedBytes: receivedBytes ?? this.receivedBytes,
        totalBytes: totalBytes ?? this.totalBytes,
        status: status ?? this.status,
        error: clearError ? null : (error ?? this.error),
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'filename': filename,
        if (filePath != null) 'filePath': filePath,
        if (mimeType != null) 'mimeType': mimeType,
        'receivedBytes': receivedBytes,
        'totalBytes': totalBytes,
        'status': status.name,
        if (error != null) 'error': error,
        'createdAt': createdAt.toIso8601String(),
      };

  factory DownloadItem.fromJson(Map<String, dynamic> json) {
    final statusName = json['status']?.toString() ?? '';
    final parsedStatus = DownloadStatus.values.firstWhere(
      (s) => s.name == statusName,
      orElse: () => DownloadStatus.failed,
    );
    // In-flight transfers from a previous killed process cannot resume.
    final normalizedStatus = parsedStatus == DownloadStatus.downloading
        ? DownloadStatus.cancelled
        : parsedStatus;
    return DownloadItem(
      id: json['id']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      filename: json['filename']?.toString() ?? 'download',
      filePath: json['filePath']?.toString(),
      mimeType: json['mimeType']?.toString(),
      receivedBytes: (json['receivedBytes'] as num?)?.toInt() ?? 0,
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? -1,
      status: normalizedStatus,
      error: json['error']?.toString(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
