import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:operon/models/download_item.dart';
import 'package:operon/services/download_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('operon_dl_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('sanitizeFilename cleans illegal characters and falls back to URL', () {
    expect(
      DownloadService.sanitizeFilename('foo/bar:baz?.pdf', 'https://x.com/a'),
      'foo_bar_baz_.pdf',
    );
    expect(
      DownloadService.sanitizeFilename(null, 'https://example.com/files/report.csv?token=1'),
      'report.csv',
    );
    expect(
      DownloadService.sanitizeFilename(null, 'https://example.com/'),
      startsWith('download_'),
    );
  });

  test('enqueue streams file to disk and deduplicates colliding filenames',
      () async {
    final payload = utf8.encode('hello-operon-download');
    final client = MockClient.streaming((request, bodyStream) async {
      return http.StreamedResponse(
        Stream.value(payload),
        200,
        contentLength: payload.length,
        headers: {'content-type': 'text/plain'},
      );
    });

    String? openedPath;
    String? openedMime;
    final service = DownloadService(
      clientFactory: () => client,
      directoryResolver: () async => tempDir,
      fileOpener: (path, mimeType) async {
        openedPath = path;
        openedMime = mimeType;
        return true;
      },
    );
    await service.init();

    final firstDone = Completer<DownloadItem>();
    final first = await service.enqueue(
      url: 'https://example.com/demo.txt',
      suggestedFilename: 'demo.txt',
      mimeType: 'text/plain',
      onFinished: firstDone.complete,
    );
    final finishedFirst = await firstDone.future;
    expect(finishedFirst.id, first.id);
    expect(finishedFirst.status, DownloadStatus.completed);
    expect(finishedFirst.filename, 'demo.txt');
    expect(finishedFirst.receivedBytes, payload.length);
    expect(await File(finishedFirst.filePath!).readAsString(),
        'hello-operon-download');

    final secondDone = Completer<DownloadItem>();
    await service.enqueue(
      url: 'https://example.com/demo.txt',
      suggestedFilename: 'demo.txt',
      onFinished: secondDone.complete,
    );
    final finishedSecond = await secondDone.future;
    expect(finishedSecond.filename, 'demo (1).txt');
    expect(await File(finishedSecond.filePath!).exists(), true);

    final opened = await service.openFile(finishedFirst);
    expect(opened, true);
    expect(openedPath, finishedFirst.filePath);
    expect(openedMime, 'text/plain');
  });

  test('cancel aborts in-flight download and deletes partial file', () async {
    final controller = StreamController<List<int>>();
    addTearDown(() async {
      if (!controller.isClosed) await controller.close();
    });
    final client = MockClient.streaming((request, bodyStream) async {
      return http.StreamedResponse(
        controller.stream,
        200,
        contentLength: 1000,
      );
    });

    final service = DownloadService(
      clientFactory: () => client,
      directoryResolver: () async => tempDir,
    );
    await service.init();

    final finished = Completer<DownloadItem>();
    final item = await service.enqueue(
      url: 'https://example.com/big.bin',
      suggestedFilename: 'big.bin',
      onFinished: finished.complete,
    );

    controller.add([1, 2, 3, 4]);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    service.cancel(item.id);
    final cancelled = await finished.future;
    if (!controller.isClosed) await controller.close();

    expect(cancelled.status, DownloadStatus.cancelled);
    if (cancelled.filePath != null) {
      expect(await File(cancelled.filePath!).exists(), false);
    }
  });

  test('init converts stale downloading records from prior crash to cancelled',
      () async {
    final stale = DownloadItem(
      id: 'dl_old',
      url: 'https://example.com/stale.zip',
      filename: 'stale.zip',
      filePath: '${tempDir.path}/stale.zip',
      totalBytes: 500,
      receivedBytes: 120,
      status: DownloadStatus.downloading,
      createdAt: DateTime(2026, 1, 1),
    );
    SharedPreferences.setMockInitialValues({
      'pref_download_history': jsonEncode([stale.toJson()]),
    });

    final service = DownloadService(directoryResolver: () async => tempDir);
    await service.init();

    expect(service.items, hasLength(1));
    expect(service.items.first.status, DownloadStatus.cancelled);
  });
}
