import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../models/agent_attachment.dart';

/// Turning a picked file into something a model can be sent.
///
/// Deliberately separate from the picker call so the rules — what counts as an
/// image, how big is too big, how a text file is decoded — are testable without
/// a file dialog.
class AttachmentReader {
  static const Set<String> _imageExtensions = {
    'png',
    'jpg',
    'jpeg',
    'webp',
    'gif',
    'bmp',
    'heic',
    'heif',
  };

  /// Reads one file. Returns null with a reason the caller can show.
  static Future<AttachmentResult> read(String path, {String? name}) async {
    final fileName = name ?? path.split(Platform.pathSeparator).last;
    final file = File(path);
    if (!await file.exists()) {
      return AttachmentResult.failed('找不到这个文件：$fileName');
    }
    final size = await file.length();
    final extension = fileName.toLowerCase().split('.').last;

    if (_imageExtensions.contains(extension)) {
      if (size > AgentAttachment.maxImageBytes) {
        return AttachmentResult.failed(
          '图片太大了（${_mb(size)}，上限 ${_mb(AgentAttachment.maxImageBytes)}）。'
          '先在相册里压缩一下再试。',
        );
      }
      final bytes = await file.readAsBytes();
      return AttachmentResult.ok(AgentAttachment.image(
        name: fileName,
        base64: base64Encode(bytes),
        sizeBytes: size,
      ));
    }

    // Everything else is treated as text. A binary that happens to have a
    // readable name would otherwise arrive as mojibake the model then reasons
    // about, which is worse than refusing it.
    final bytes = await file.readAsBytes();
    if (bytes.take(4096).contains(0)) {
      return AttachmentResult.failed('这是二进制文件，只能附上图片或文本：$fileName');
    }
    final text = utf8.decode(bytes, allowMalformed: true);
    if (text.trim().isEmpty) {
      return AttachmentResult.failed('这个文件是空的：$fileName');
    }
    if (text.length > AgentAttachment.maxTextChars) {
      return AttachmentResult.failed(
        '文本太长了（${text.length} 字，上限 ${AgentAttachment.maxTextChars}）。'
        '请先截取需要的部分。',
      );
    }
    return AttachmentResult.ok(AgentAttachment.text(
      name: fileName,
      text: text,
      sizeBytes: size,
    ));
  }

  /// Opens the system picker and reads what came back.
  static Future<AttachmentPick> pick() async {
    final picked = await FilePicker.pickFiles(allowMultiple: false);
    if (picked == null || picked.files.isEmpty) {
      return const AttachmentPick.cancelled();
    }
    final file = picked.files.single;
    final path = file.path;
    if (path == null) {
      return const AttachmentPick.failed('这个文件无法读取（没有本地路径）');
    }
    final result = await read(path, name: file.name);
    return result.attachment == null
        ? AttachmentPick.failed(result.message ?? '无法读取这个文件')
        : AttachmentPick.picked(result.attachment!);
  }

  static String _mb(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class AttachmentResult {
  const AttachmentResult._(this.attachment, this.message);

  const AttachmentResult.ok(AgentAttachment attachment)
      : this._(attachment, null);

  const AttachmentResult.failed(String message) : this._(null, message);

  final AgentAttachment? attachment;
  final String? message;
}

/// What a pick attempt produced: a file, a message, or nothing (cancelled).
class AttachmentPick {
  const AttachmentPick._(this.attachment, this.message, this.cancelled);

  const AttachmentPick.cancelled() : this._(null, null, true);

  const AttachmentPick.picked(AgentAttachment attachment)
      : this._(attachment, null, false);

  const AttachmentPick.failed(String message) : this._(null, message, false);

  final AgentAttachment? attachment;
  final String? message;
  final bool cancelled;
}
