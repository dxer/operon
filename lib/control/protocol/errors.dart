/// Why a control-layer call failed, in a form the agent can act on.
///
/// The set is deliberately small and every value means one thing: an agent that
/// gets [staleRef] must observe again, while [notHittable] means the element is
/// covered and the caller has to scroll or dismiss the overlay first. A single
/// "failed" string would leave it guessing.
enum ControlErrorCode {
  /// The WebView's DevTools socket could not be reached or has gone away.
  channelUnavailable,

  /// The tab has no DevTools target yet, or it went away.
  targetMissing,

  /// The accessibility capture failed or came back empty.
  captureFailed,

  /// The ref is not from the document that is on screen now.
  staleRef,

  /// The ref was never shown to the caller.
  unknownRef,

  /// No node matches what was asked for.
  notFound,

  /// More than one node matches, and picking one would be a guess.
  ambiguous,

  /// The node is in the document but not rendered.
  notVisible,

  /// Something else is on top of the node's point.
  notHittable,

  /// The control is disabled.
  disabled,

  /// The node cannot take text.
  notEditable,

  /// The caller's arguments cannot be acted on: a missing field, or two that
  /// contradict each other.
  badArguments,

  /// The node is in the document and visible, but it keeps moving.
  notStable,

  /// The budget ran out.
  timeout,

  /// A navigation started and interrupted the call.
  navigation,

  /// A page dialog is open, so the page is frozen.
  dialogOpen,

  /// The site is on the user's block list.
  blocked,

  /// The action needs a person (payment, password, code).
  sensitive,

  /// The WebView build does not have the CDP domain this needs.
  unsupported,

  /// A protocol-level failure we do not classify.
  internal,
}

/// A typed failure from the control layer.
class ControlException implements Exception {
  const ControlException(
    this.code,
    this.message, {
    this.hint,
    this.details,
  });

  final ControlErrorCode code;
  final String message;

  /// What the caller can do about it, when the layer knows.
  final String? hint;

  /// Protocol detail kept out of [message]: CDP method, node id, raw text.
  final Map<String, Object?>? details;

  Map<String, Object?> toJson() => {
        'code': code.name,
        'message': message,
        if (hint != null) 'hint': hint,
        if (details != null) 'details': details,
      };

  @override
  String toString() =>
      'ControlException(${code.name}): $message${hint == null ? '' : ' — $hint'}';
}
