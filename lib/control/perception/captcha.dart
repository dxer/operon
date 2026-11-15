import 'ax.dart';

/// A human-verification challenge the agent must not try to solve.
///
/// The old engine detected these from CSS selectors in injected script. The
/// accessibility tree answers the same question from the side the browser
/// exposes to assistive technology, which is also what the layer already reads,
/// so nothing extra has to run in the page.
class CaptchaInfo {
  const CaptchaInfo({required this.present, this.kind, this.evidence});

  static const CaptchaInfo none = CaptchaInfo(present: false);

  final bool present;

  /// A short name for the user: 人机验证 / Cloudflare / 滑块验证 …
  final String? kind;

  /// What matched, kept for the self-check and for the log.
  final String? evidence;

  Map<String, Object?> toJson() => {
        'present': present,
        if (kind != null) 'kind': kind,
        if (evidence != null) 'evidence': evidence,
      };
}

/// Name fragments that only appear on a verification challenge.
///
/// Kept narrow on purpose: a page with a "验证码" field in a login form is not a
/// challenge, so a bare 验证码 only counts when it belongs to a dialog or an
/// iframe. The full phrases below are unambiguous.
const List<(String, String)> _challengePhrases = [
  // The named products come first: "cloudflare" appears inside a Turnstile
  // frame's name too, and the more specific name is the useful one.
  ('turnstile', 'Cloudflare Turnstile'),
  ('arkose', 'Arkose Labs'),
  ('geetest', 'Geetest'),
  ("i'm not a robot", 'reCAPTCHA'),
  ('i am not a robot', 'reCAPTCHA'),
  ('checking your browser', 'Cloudflare'),
  ('just a moment', 'Cloudflare'),
  ('cloudflare', 'Cloudflare'),
  ('verify you are human', '人机验证'),
  ('verify you are a human', '人机验证'),
  ('滑动验证', '滑块验证'),
  ('拖动滑块', '滑块验证'),
  ('请完成安全验证', '人机验证'),
  ('请完成验证', '人机验证'),
  ('人机验证', '人机验证'),
  ('安全验证', '人机验证'),
  ('行为验证', '人机验证'),
];

/// Roles whose name is trustworthy evidence of a challenge: text inside a
/// paragraph can say anything, a dialog or a frame cannot fake its own role.
const Set<String> _evidenceRoles = {
  'dialog',
  'alertdialog',
  'Iframe',
  'WebArea',
  'RootWebArea',
  'image',
};

const List<String> _challengeButtonPhrases = [
  "i'm not a robot",
  'i am not a robot',
  'not a robot',
  'verify you are human',
  'verify you are a human',
  '我不是机器人',
  '我是人类',
  '点击完成验证',
  '点击进行人机验证',
  '开始人机验证',
  '点击验证',
];

CaptchaInfo detectCaptcha(List<AxNode> nodes) {
  for (final node in nodes) {
    if (node.ignored) continue;
    final name = node.name.trim().toLowerCase();
    if (name.isEmpty) continue;
    if (!_evidenceRoles.contains(node.role) && node.role != 'checkbox') continue;
    for (final (phrase, kind) in _challengePhrases) {
      if (name.contains(phrase)) {
        return CaptchaInfo(
          present: true,
          kind: kind,
          evidence: '${node.role}: $name',
        );
      }
    }
  }

  // A checkbox or button labelled explicitly as a bot challenge (not ordinary
  // SMS/account labels such as "获取验证码" or "实名验证").
  for (final node in nodes) {
    if (node.ignored) continue;
    if (node.role != 'checkbox' && node.role != 'button') continue;
    final name = node.name.trim().toLowerCase();
    if (_challengeButtonPhrases.any(name.contains)) {
      return CaptchaInfo(
        present: true,
        kind: '人机验证',
        evidence: '${node.role}: ${node.name}',
      );
    }
  }
  return CaptchaInfo.none;
}
