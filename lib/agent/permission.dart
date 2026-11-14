/// How a write is classified before it is dispatched.
///
/// Detection is best effort; enforcement is strict. A miss costs a
/// confirmation the user did not need. A false negative would send something
/// they never approved, so the word lists are deliberately generous, and a
/// destructive match can never be waived by a site rule.
class WriteAssessment {
  const WriteAssessment({
    required this.writes,
    this.destructive = false,
    this.handoff = false,
    this.kind = '',
  });

  static const WriteAssessment none = WriteAssessment(writes: false);

  final bool writes;

  /// A page dialog or a deletion: asks in every mode, but the agent may still
  /// do it once the user says yes.
  final bool destructive;

  /// Money or a credential. The agent never does this, in any mode, whatever
  /// the user answers: it hands the step over instead.
  ///
  /// Nanobrowser draws the same line, and it is the right one — "may I submit
  /// this form" and "may I type your card number" are different questions, and
  /// only the first one belongs in a dialog with a yes button.
  final bool handoff;

  /// A short word for the confirmation card: 发布 / 发送 / 删除 / 支付 …
  final String kind;

  String get label => kind.isEmpty ? '写入' : kind;
}

/// Money and credentials: the agent hands these to the user and never does
/// them itself.
const List<String> _handoffWords = [
  '支付',
  '付款',
  '转账',
  '充值',
  '购买',
  '下单',
  '结算',
  '密码',
  '验证码',
  '短信码',
  '身份证',
  '银行卡',
  '信用卡',
  'pay now',
  'payment',
  'checkout',
  'purchase',
  'password',
  'passcode',
  'credit card',
  'card number',
  'cvv',
  'verification code',
  'one-time code',
  'otp',
];

/// Destructive but reversible-by-asking: the agent may do it after a yes.
const List<String> _destructiveWords = [
  '删除',
  '移除',
  '清空',
  '退订',
  '取消订单',
  '解绑',
  '注销',
  'delete',
  'remove',
  'unsubscribe',
  'destroy',
  'deactivate',
];

const List<String> _submitWords = [
  '发送',
  '发布',
  '提交',
  '回复',
  '评论',
  '保存',
  '点赞',
  '关注',
  '转发',
  '分享',
  '确认',
  '同意',
  '允许',
  'send',
  'publish',
  'post',
  'submit',
  'reply',
  'comment',
  'save',
  'like',
  'follow',
  'share',
  'confirm',
  'accept',
];

const List<String> _draftWords = ['草稿', 'draft', 'save draft', '存草稿'];

/// Classifies one tool call.
///
/// [targetLabel] is the outline line of the element being clicked (`button
/// "发送"`), when the caller knows it: the label is the only evidence available
/// for what a click will do.
WriteAssessment assessWrite(
  String tool,
  Map<String, Object?> args, {
  String? targetLabel,
}) {
  final label = (targetLabel ?? '').trim().toLowerCase();

  // Saving a draft is not publishing: it must never stand in for a send, and
  // it must not be forced through a confirmation either.
  if (label.isNotEmpty && _draftWords.any(label.contains)) {
    return const WriteAssessment(writes: false, kind: '草稿');
  }

  switch (tool) {
    case 'type':
      // A value typed into a field marked secret is a credential: the agent
      // refuses it even when the user would approve.
      if (args['secret'] == true || args['secret'] == 'true') {
        return const WriteAssessment(
          writes: true,
          destructive: true,
          handoff: true,
          kind: '填写密钥',
        );
      }
      if (args['submit'] == true || args['submit'] == 'true') {
        return const WriteAssessment(writes: true, kind: '提交');
      }
      // Typing on its own stays on the machine.
      return WriteAssessment.none;
    case 'press':
      final key = (args['key'] ?? '').toString().toLowerCase();
      if (key == 'enter') {
        return const WriteAssessment(writes: true, kind: '提交');
      }
      return WriteAssessment.none;
    case 'handle_dialog':
      final accept = args['accept'] == true || args['accept'] == 'true';
      if (accept) {
        // The page's own dialog can be anything, including a payment, so it is
        // the user's to accept: a page prompt is exactly what cannot be
        // pre-classified.
        return const WriteAssessment(
          writes: true,
          destructive: true,
          handoff: true,
          kind: '页面弹窗',
        );
      }
      return const WriteAssessment(writes: true, kind: '关闭弹窗');
    case 'click':
      if (label.isEmpty) {
        // Nothing says what this click will do, so it asks rather than assumes.
        return const WriteAssessment(writes: true, kind: '点击');
      }
      final text = label;
      if (_handoffWords.any(text.contains)) {
        return const WriteAssessment(
          writes: true,
          destructive: true,
          handoff: true,
          kind: '支付/填写密钥',
        );
      }
      if (_destructiveWords.any(text.contains)) {
        return const WriteAssessment(writes: true, destructive: true, kind: '删除');
      }
      if (_submitWords.any(text.contains)) {
        return const WriteAssessment(writes: true, kind: '提交');
      }
      // A click whose label says nothing about writing is navigation or a
      // toggle: not a side effect by itself.
      return WriteAssessment.none;
    default:
      return WriteAssessment.none;
  }
}
