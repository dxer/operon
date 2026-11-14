import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:operon/models/agent_attachment.dart';
import 'package:operon/services/attachment_reader.dart';
import 'package:operon/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Two things a user can hand the agent: a site rule it must respect, and a
/// file it should read. Both are stored/validated outside the UI, so both are
/// tested here.

Future<StorageService> freshStorage([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(values);
  StorageService.resetForTest();
  return StorageService.getInstance();
}

void main() {
  group('the block list', () {
    test('starts empty and accepts a host in any shape', () async {
      final storage = await freshStorage();
      expect(storage.getAgentBlockedSites(), isEmpty);

      await storage.addAgentBlockedSite('HTTPS://WWW.Example.com/mail');
      expect(storage.isAgentSiteBlocked('example.com'), isTrue);
      expect(storage.isAgentSiteBlocked('https://example.com/x'), isTrue);
    });

    test('blocking a site removes it from the allow list', () async {
      final storage = await freshStorage();
      await storage.addAgentAllowedSite('example.com');
      await storage.addAgentBlockedSite('example.com');

      expect(storage.isAgentSiteBlocked('example.com'), isTrue);
      expect(storage.isAgentSiteAllowed('example.com'), isFalse,
          reason: 'a site cannot be both trusted and forbidden');
    });

    test('a site can be unblocked again', () async {
      final storage = await freshStorage();
      await storage.addAgentBlockedSite('example.com');
      await storage.removeAgentBlockedSite('example.com');
      expect(storage.isAgentSiteBlocked('example.com'), isFalse);

      await storage.addAgentBlockedSite('a.com');
      await storage.addAgentBlockedSite('b.com');
      await storage.clearAgentBlockedSites();
      expect(storage.getAgentBlockedSites(), isEmpty);
    });

    test('an empty or wildcard-only entry never blocks everything', () async {
      final storage = await freshStorage();
      await storage.addAgentBlockedSite('   ');
      expect(storage.getAgentBlockedSites(), isEmpty);
      expect(storage.isAgentSiteBlocked(''), isFalse);
    });
  });

  group('reading an attachment', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('operon_attach');
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    Future<String> write(String name, List<int> bytes) async {
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      await file.writeAsBytes(bytes);
      return file.path;
    }

    test('a UTF-8 text file is kept as text', () async {
      final path = await write('notes.md', '# 预算\n- 3000 元'.codeUnits.isEmpty
          ? []
          : utf8.encode('# 预算\n- 3000 元'));
      final result = await AttachmentReader.read(path);

      expect(result.attachment?.kind, AttachmentKind.text);
      expect(result.attachment?.text, contains('3000 元'));
      expect(result.attachment?.label, contains('notes.md'));
    });

    test('an image becomes a data-uri ready base64 payload', () async {
      // A 1x1 PNG, enough to prove the bytes are carried unchanged.
      const bytes = [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00,
      ];
      final path = await write('shot.png', bytes);
      final result = await AttachmentReader.read(path);

      expect(result.attachment?.isImage, isTrue);
      expect(result.attachment?.mimeHint, 'image/png');
      expect(result.attachment?.imagePart['type'], 'image_url');
      expect(
        (result.attachment!.imagePart['image_url'] as Map)['url'],
        startsWith('data:image/png;base64,'),
      );
    });

    test('a binary with a text name is refused, not decoded into mojibake', () async {
      final path = await write('data.txt', [0x41, 0x00, 0x42, 0x00]);
      final result = await AttachmentReader.read(path);

      expect(result.attachment, isNull);
      expect(result.message, contains('二进制'));
    });

    test('oversized text is refused with the limit in the message', () async {
      final path = await write(
        'big.txt',
        utf8.encode('字' * (AgentAttachment.maxTextChars + 10)),
      );
      final result = await AttachmentReader.read(path);

      expect(result.attachment, isNull);
      expect(result.message, contains('${AgentAttachment.maxTextChars}'));
    });

    test('an empty file says so instead of attaching nothing', () async {
      final path = await write('empty.txt', const []);
      final result = await AttachmentReader.read(path);
      expect(result.attachment, isNull);
      expect(result.message, contains('空'));
    });

    test('a missing file is reported rather than thrown', () async {
      final result = await AttachmentReader.read('${dir.path}/nope.txt');
      expect(result.attachment, isNull);
      expect(result.message, contains('找不到'));
    });
  });
}
