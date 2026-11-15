import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Handing a result to another app.
///
/// A browser that can only put text on the clipboard makes the user do the last
/// step themselves. The share sheet is that step: send it to a chat, a note, a
/// mail, a spreadsheet. It never reports success it did not see — Android tells
/// us whether the sheet opened, not whether anything was sent.
class ShareService {
  const ShareService();

  Future<bool> shareText(String text, {String? subject}) async {
    if (text.trim().isEmpty) return false;
    try {
      await Share.share(text, subject: subject);
      return true;
    } catch (_) {
      // A device with no share target, or a platform without the plugin: the
      // caller still has the clipboard path, so this is not worth an error.
      return false;
    }
  }

  /// Shares a file instead of a string.
  ///
  /// A CSV that arrives as a chat message is a wall of commas; the whole point
  /// of the export is a spreadsheet. The file goes to the cache directory
  /// because it is a hand-off, not a document this app owns — Android may clear
  /// it, and nothing breaks when it does.
  Future<bool> shareTextFile({
    required String fileName,
    required String content,
    required String mimeType,
    String? subject,
  }) async {
    if (fileName.isEmpty || content.isEmpty) return false;
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}$fileName');
      await file.writeAsString(content, flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: mimeType)],
        subject: subject,
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
