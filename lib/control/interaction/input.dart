import '../transport/cdp_connection.dart';

/// How a click reaches the page.
///
/// A mouse event works on pages that were built for a desktop pointer; a touch
/// tap is what a phone sends, and the browser turns it into the compatibility
/// mouse events and `click` a page expects. The default follows the page: a
/// mobile page gets a touch, everything else a mouse.
enum InputMode { auto, touch, mouse }

/// The key descriptions CDP wants, for the keys an agent actually presses.
class KeySpec {
  const KeySpec({
    required this.key,
    required this.code,
    required this.virtualKeyCode,
    this.text,
    this.textUnmodified,
  });

  final String key;
  final String code;
  final int virtualKeyCode;

  /// Text the key produces; absent for keys that only navigate or edit.
  final String? text;
  final String? textUnmodified;

  bool get producesText => text != null && text!.isNotEmpty;
}

const Map<String, KeySpec> _keys = {
  'Enter': KeySpec(
    key: 'Enter',
    code: 'Enter',
    virtualKeyCode: 13,
    text: '\r',
    textUnmodified: '\r',
  ),
  'Tab': KeySpec(key: 'Tab', code: 'Tab', virtualKeyCode: 9),
  'Escape': KeySpec(key: 'Escape', code: 'Escape', virtualKeyCode: 27),
  'Backspace': KeySpec(key: 'Backspace', code: 'Backspace', virtualKeyCode: 8),
  'Delete': KeySpec(key: 'Delete', code: 'Delete', virtualKeyCode: 46),
  ' ': KeySpec(key: ' ', code: 'Space', virtualKeyCode: 32, text: ' '),
  'Space': KeySpec(key: ' ', code: 'Space', virtualKeyCode: 32, text: ' '),
  'ArrowUp': KeySpec(key: 'ArrowUp', code: 'ArrowUp', virtualKeyCode: 38),
  'ArrowDown': KeySpec(key: 'ArrowDown', code: 'ArrowDown', virtualKeyCode: 40),
  'ArrowLeft': KeySpec(key: 'ArrowLeft', code: 'ArrowLeft', virtualKeyCode: 37),
  'ArrowRight': KeySpec(key: 'ArrowRight', code: 'ArrowRight', virtualKeyCode: 39),
  'Home': KeySpec(key: 'Home', code: 'Home', virtualKeyCode: 36),
  'End': KeySpec(key: 'End', code: 'End', virtualKeyCode: 35),
  'PageUp': KeySpec(key: 'PageUp', code: 'PageUp', virtualKeyCode: 33),
  'PageDown': KeySpec(key: 'PageDown', code: 'PageDown', virtualKeyCode: 34),
};

/// Returns the spec for [key], or null when the layer does not know it.
KeySpec? keySpecFor(String key) {
  final direct = _keys[key];
  if (direct != null) return direct;
  final normalized = key.length == 1 ? key.toUpperCase() : key;
  return _keys[normalized];
}

/// Dispatches a trusted key event pair (down, up).
///
/// Keys that produce text send `keyDown` with the text; keys that only move or
/// edit send `rawKeyDown`, which is what the browser sends for them too.
Future<void> pressKey(
  CdpConnection connection,
  KeySpec spec, {
  String? sessionId,
  int modifiers = 0,
}) async {
  final base = <String, Object?>{
    'key': spec.key,
    'code': spec.code,
    'windowsVirtualKeyCode': spec.virtualKeyCode,
    'nativeVirtualKeyCode': spec.virtualKeyCode,
    if (modifiers != 0) 'modifiers': modifiers,
  };
  await connection.send(
    'Input.dispatchKeyEvent',
    sessionId: sessionId,
    params: {
      ...base,
      'type': spec.producesText ? 'keyDown' : 'rawKeyDown',
      if (spec.producesText) 'text': spec.text,
      if (spec.textUnmodified != null) 'unmodifiedText': spec.textUnmodified,
    },
  );
  await connection.send(
    'Input.dispatchKeyEvent',
    sessionId: sessionId,
    params: {...base, 'type': 'keyUp'},
  );
}

/// Inserts text into whatever holds focus.
///
/// `Input.insertText` goes through the browser's editing pipeline, so a
/// controlled input receives a real `input` event and its framework state
/// updates. Writing the value from script would leave React, Vue and every
/// form library out of sync.
Future<void> insertText(
  CdpConnection connection,
  String text, {
  String? sessionId,
}) async {
  if (text.isEmpty) return;
  await connection.send(
    'Input.insertText',
    sessionId: sessionId,
    params: {'text': text},
  );
}

/// Selects the focused field's whole value, so the next insert replaces it.
///
/// Uses CDP's editing-command hook rather than a keyboard shortcut per platform.
Future<void> selectAll(CdpConnection connection, {String? sessionId}) async {
  await connection.send(
    'Input.dispatchKeyEvent',
    sessionId: sessionId,
    params: {
      'type': 'rawKeyDown',
      'key': 'a',
      'code': 'KeyA',
      'windowsVirtualKeyCode': 65,
      'nativeVirtualKeyCode': 65,
      'modifiers': 2,
      'commands': ['selectAll'],
    },
  );
}

/// One tap at viewport coordinates.
Future<void> tapAt(
  CdpConnection connection, {
  required double x,
  required double y,
  required InputMode mode,
  String? sessionId,
}) async {
  if (mode == InputMode.touch) {
    await connection.send(
      'Input.dispatchTouchEvent',
      sessionId: sessionId,
      params: {
        'type': 'touchStart',
        'touchPoints': [
          {
            'x': x,
            'y': y,
            'radiusX': 2,
            'radiusY': 2,
            'force': 1,
            'id': 1,
          },
        ],
      },
    );
    await connection.send(
      'Input.dispatchTouchEvent',
      sessionId: sessionId,
      params: {'type': 'touchEnd', 'touchPoints': <Object?>[]},
    );
    return;
  }
  await connection.send(
    'Input.dispatchMouseEvent',
    sessionId: sessionId,
    params: {'type': 'mouseMoved', 'x': x, 'y': y, 'button': 'none'},
  );
  await connection.send(
    'Input.dispatchMouseEvent',
    sessionId: sessionId,
    params: {
      'type': 'mousePressed',
      'x': x,
      'y': y,
      'button': 'left',
      'buttons': 1,
      'clickCount': 1,
    },
  );
  await connection.send(
    'Input.dispatchMouseEvent',
    sessionId: sessionId,
    params: {
      'type': 'mouseReleased',
      'x': x,
      'y': y,
      'button': 'left',
      'buttons': 0,
      'clickCount': 1,
    },
  );
}

/// Moves the pointer over a point, which is what opens hover menus.
Future<void> hoverAt(
  CdpConnection connection, {
  required double x,
  required double y,
  String? sessionId,
}) async {
  await connection.send(
    'Input.dispatchMouseEvent',
    sessionId: sessionId,
    params: {'type': 'mouseMoved', 'x': x, 'y': y, 'button': 'none'},
  );
}

/// Scrolls at a point.
Future<void> wheelAt(
  CdpConnection connection, {
  required double x,
  required double y,
  required double deltaY,
  double deltaX = 0,
  String? sessionId,
}) async {
  await connection.send(
    'Input.dispatchMouseEvent',
    sessionId: sessionId,
    params: {
      'type': 'mouseWheel',
      'x': x,
      'y': y,
      'deltaX': deltaX,
      'deltaY': deltaY,
      'button': 'none',
    },
  );
}
