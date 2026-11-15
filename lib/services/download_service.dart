import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/download_item.dart';
import '../utils/cancellation.dart';

/// Streams browser downloads directly to disk with progress, cancel/retry, and
/// persistence across sessions.
class DownloadService extends ChangeNotifier {
  DownloadService({
    http.Client Function()? clientFactory,
    Future<Directory> Function()? directoryResolver,
    Future<bool> Function(String path, String? mimeType)? fileOpener,
  })  : _clientFactory = clientFactory ?? http.Client.new,
        _directoryResolver = directoryResolver ?? _defaultDirectory,
        _fileOpener = fileOpener ?? _defaultOpenFile;

  static DownloadService? _instance;

  static DownloadService get instance => _instance ??= DownloadService();

  static const String _prefsKey = 'pref_download_history';
  static const int _maxEntries = 100;
  static const MethodChannel _filesChannel = MethodChannel('operon/files');

  final http.Client Function() _clientFactory;
  final Future<Directory> Function() _directoryResolver;
  final Future<bool> Function(String path, String? mimeType) _fileOpener;

  final List<DownloadItem> _items = <DownloadItem>[];
  final Map<String, CancellationToken> _activeTokens =
      <String, CancellationToken>{};
  bool _initialized = false;

  List<DownloadItem> get items => List.unmodifiable(_items);

  int get activeCount =>
      _items.where((i) => i.status == DownloadStatus.downloading).length;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _items
            ..clear()
            ..addAll(
              decoded
                  .whereType<Map>()
                  .map(
                    (e) => DownloadItem.fromJson(Map<String, dynamic>.from(e)),
                  )
                  .where((e) => e.id.isNotEmpty && e.url.isNotEmpty),
            );
        }
      }
    } catch (_) {
      // Corrupt history should not block downloads.
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final trimmed = _items.take(_maxEntries).toList(growable: false);
      await prefs.setString(
        _prefsKey,
        jsonEncode([for (final item in trimmed) item.toJson()]),
      );
    } catch (_) {
      // Best-effort persistence.
    }
  }

  static Future<Directory> _defaultDirectory() async {
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) return downloads;
    } catch (_) {
      // Fallback to application documents directory.
    }
    final docs = await getApplicationDocumentsDirectory();
    final sub = Directory('${docs.path}${Platform.pathSeparator}downloads');
    if (!await sub.exists()) {
      await sub.create(recursive: true);
    }
    return sub;
  }

  static Future<bool> _defaultOpenFile(String path, String? mimeType) async {
    try {
      final opened = await _filesChannel.invokeMethod<bool>('openFile', {
        'path': path,
        'mimeType': mimeType,
      });
      if (opened == true) return true;
    } on MissingPluginException {
      // Fall through to share sheet when no native channel exists.
    } on PlatformException {
      // Fall through to share sheet.
    }
    try {
      await Share.shareXFiles([XFile(path)]);
      return true;
    } catch (_) {
      return false;
    }
  }

  static String sanitizeFilename(String? suggested, String url) {
    var name = (suggested ?? '').trim();
    if (name.isEmpty) {
      final parsed = Uri.tryParse(url);
      if (parsed != null && parsed.pathSegments.isNotEmpty) {
        name = parsed.pathSegments.last.trim();
      }
    }
    if (name.isEmpty) {
      name = 'download_${DateTime.now().millisecondsSinceEpoch}';
    }
    name = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return name.isEmpty ? 'download' : name;
  }

  Future<File> _uniqueTargetFile(Directory dir, String filename) async {
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final dot = filename.lastIndexOf('.');
    final stem = dot > 0 ? filename.substring(0, dot) : filename;
    final ext = dot > 0 ? filename.substring(dot) : '';

    var candidate = File('${dir.path}${Platform.pathSeparator}$filename');
    var index = 1;
    while (await candidate.exists()) {
      candidate = File('${dir.path}${Platform.pathSeparator}$stem ($index)$ext');
      index++;
    }
    return candidate;
  }

  /// Starts downloading [url] in the background and returns the queued item.
  Future<DownloadItem> enqueue({
    required String url,
    String? suggestedFilename,
    String? mimeType,
    String? userAgent,
    String? cookieHeader,
    int contentLength = -1,
    void Function(DownloadItem item)? onFinished,
  }) async {
    await init();
    final filename = sanitizeFilename(suggestedFilename, url);
    final id = 'dl_${DateTime.now().microsecondsSinceEpoch}_${_items.length}';
    final item = DownloadItem(
      id: id,
      url: url,
      filename: filename,
      mimeType: mimeType,
      totalBytes: contentLength,
      status: DownloadStatus.downloading,
      createdAt: DateTime.now(),
    );
    _items.insert(0, item);
    if (_items.length > _maxEntries) {
      _items.removeRange(_maxEntries, _items.length);
    }
    notifyListeners();
    unawaited(_persist());

    unawaited(_runTransfer(
      item,
      userAgent: userAgent,
      cookieHeader: cookieHeader,
      onFinished: onFinished,
    ));
    return item;
  }

  Future<void> _runTransfer(
    DownloadItem initial, {
    String? userAgent,
    String? cookieHeader,
    void Function(DownloadItem item)? onFinished,
  }) async {
    final token = CancellationToken();
    _activeTokens[initial.id] = token;
    final abort = Completer<void>();
    token.whenCancelled.then((_) {
      if (!abort.isCompleted) abort.complete();
    });

    final client = _clientFactory();
    IOSink? sink;
    File? targetFile;
    try {
      final uri = Uri.tryParse(initial.url);
      if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
        throw Exception('不支持的下载链接');
      }
      final request = http.AbortableRequest(
        'GET',
        uri,
        abortTrigger: abort.future,
      );
      if (userAgent != null && userAgent.isNotEmpty) {
        request.headers['User-Agent'] = userAgent;
      }
      if (cookieHeader != null && cookieHeader.isNotEmpty) {
        request.headers['Cookie'] = cookieHeader;
      }

      final response = await client.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final dir = await _directoryResolver();
      targetFile = await _uniqueTargetFile(dir, initial.filename);
      sink = targetFile.openWrite();

      final total = response.contentLength ?? initial.totalBytes;
      final mime = response.headers['content-type'] ?? initial.mimeType;
      final savedName = targetFile.uri.pathSegments.isNotEmpty
          ? targetFile.uri.pathSegments.last
          : initial.filename;
      var received = 0;
      var lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

      _replaceItem(initial.copyWith(
        filename: savedName,
        filePath: targetFile.path,
        mimeType: mime,
        totalBytes: total,
      ));

      final streamDone = Completer<void>();
      late final StreamSubscription<List<int>> sub;
      sub = response.stream.listen(
        (chunk) {
          if (token.isCancelled) {
            if (!streamDone.isCompleted) {
              streamDone.completeError(const _DownloadCancelled());
            }
            return;
          }
          sink?.add(chunk);
          received += chunk.length;
          final now = DateTime.now();
          if (now.difference(lastEmit).inMilliseconds >= 180) {
            lastEmit = now;
            _updateById(
              initial.id,
              (cur) => cur.copyWith(receivedBytes: received),
            );
          }
        },
        onError: (Object err, StackTrace st) {
          if (!streamDone.isCompleted) streamDone.completeError(err, st);
        },
        onDone: () {
          if (!streamDone.isCompleted) streamDone.complete();
        },
        cancelOnError: true,
      );

      unawaited(token.whenCancelled.then((_) async {
        await sub.cancel();
        if (!streamDone.isCompleted) {
          streamDone.completeError(const _DownloadCancelled());
        }
      }));

      try {
        await streamDone.future;
      } finally {
        await sub.cancel();
      }

      await sink.flush();
      await sink.close();
      sink = null;

      final done = _updateById(
        initial.id,
        (cur) => cur.copyWith(
          filename: savedName,
          filePath: targetFile!.path,
          receivedBytes: received,
          totalBytes: total > 0 ? total : received,
          status: DownloadStatus.completed,
          clearError: true,
        ),
      );
      await _persist();
      if (done != null) onFinished?.call(done);
    } on _DownloadCancelled {
      await _closeAndDelete(sink, targetFile);
      final cancelled = _updateById(
        initial.id,
        (cur) => cur.copyWith(status: DownloadStatus.cancelled),
      );
      await _persist();
      if (cancelled != null) onFinished?.call(cancelled);
    } on http.RequestAbortedException {
      await _closeAndDelete(sink, targetFile);
      final cancelled = _updateById(
        initial.id,
        (cur) => cur.copyWith(status: DownloadStatus.cancelled),
      );
      await _persist();
      if (cancelled != null) onFinished?.call(cancelled);
    } catch (error) {
      await _closeAndDelete(sink, targetFile);
      final failed = _updateById(
        initial.id,
        (cur) => cur.copyWith(
          status: DownloadStatus.failed,
          error: '$error'.replaceFirst('Exception: ', ''),
        ),
      );
      await _persist();
      if (failed != null) onFinished?.call(failed);
    } finally {
      _activeTokens.remove(initial.id);
      client.close();
    }
  }

  Future<void> _closeAndDelete(IOSink? sink, File? file) async {
    try {
      await sink?.close();
    } catch (_) {}
    try {
      if (file != null && await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  void cancel(String id) {
    _activeTokens[id]?.cancel();
    _updateById(id, (cur) => cur.copyWith(status: DownloadStatus.cancelled));
    unawaited(_persist());
  }

  Future<DownloadItem?> retry(String id) async {
    final index = _items.indexWhere((e) => e.id == id);
    if (index < 0) return null;
    final old = _items[index];
    if (old.status == DownloadStatus.downloading) return old;
    return enqueue(
      url: old.url,
      suggestedFilename: old.filename,
      mimeType: old.mimeType,
    );
  }

  Future<void> remove(String id, {bool deleteFile = false}) async {
    _activeTokens[id]?.cancel();
    final index = _items.indexWhere((e) => e.id == id);
    if (index < 0) return;
    final removed = _items.removeAt(index);
    notifyListeners();
    if (deleteFile && removed.filePath != null) {
      try {
        final f = File(removed.filePath!);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    await _persist();
  }

  Future<void> clearCompleted() async {
    _items.removeWhere((e) => e.status != DownloadStatus.downloading);
    notifyListeners();
    await _persist();
  }

  Future<bool> openFile(DownloadItem item) async {
    final path = item.filePath;
    if (path == null || path.isEmpty) return false;
    final exists = await File(path).exists();
    if (!exists) return false;
    return _fileOpener(path, item.mimeType);
  }

  void _replaceItem(DownloadItem updated) {
    final index = _items.indexWhere((e) => e.id == updated.id);
    if (index < 0) return;
    _items[index] = updated;
    notifyListeners();
  }

  DownloadItem? _updateById(
    String id,
    DownloadItem Function(DownloadItem cur) transform,
  ) {
    final index = _items.indexWhere((e) => e.id == id);
    if (index < 0) return null;
    final next = transform(_items[index]);
    _items[index] = next;
    notifyListeners();
    return next;
  }
}

class _DownloadCancelled implements Exception {
  const _DownloadCancelled();
}
