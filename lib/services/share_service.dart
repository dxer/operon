import 'package:share_plus/share_plus.dart';

/// Handing a result to another app.
///
/// A browser that can only put text on the clipboard makes the user do the last
/// step themselves. The share sheet is that step: send it to a chat, a note, a
/// mail. It never reports success it did not see — Android tells us whether the
/// sheet opened, not whether anything was sent.
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
}
