import 'package:flutter_test/flutter_test.dart';
import 'package:operon/views/widgets/chrome_visibility.dart';

/// Hiding the address bar while the user reads is a policy, not a widget, so the
/// policy is what gets tested: when it moves, when it refuses to, and what
/// brings it back.
void main() {
  group('scrolling', () {
    test('reading down hides the chrome', () {
      final chrome = ChromeVisibility();
      expect(chrome.onScroll(120), ChromeAction.none, reason: 'first read is the baseline');
      expect(chrome.onScroll(200), ChromeAction.hide);
      expect(chrome.hidden, isTrue);
    });

    test('a small wobble is not a gesture', () {
      final chrome = ChromeVisibility();
      chrome.onScroll(100);
      for (var y = 101.0; y < 110; y += 1) {
        expect(chrome.onScroll(y), ChromeAction.none);
      }
      expect(chrome.hidden, isFalse);
    });

    test('a wobble up then down does not add up to a gesture', () {
      final chrome = ChromeVisibility();
      chrome.onScroll(100);
      chrome.onScroll(120); // +20
      chrome.onScroll(105); // -15: direction changed, travel starts over
      expect(chrome.onScroll(125), ChromeAction.none, reason: '+20 again, still under 28');
      expect(chrome.hidden, isFalse);
    });

    test('reaching back up brings it back', () {
      final chrome = ChromeVisibility();
      chrome.onScroll(100);
      chrome.onScroll(300);
      expect(chrome.hidden, isTrue);
      expect(chrome.onScroll(250), ChromeAction.show);
      expect(chrome.hidden, isFalse);
    });

    test('at the top it is always shown', () {
      final chrome = ChromeVisibility();
      chrome.onScroll(400);
      chrome.onScroll(800);
      expect(chrome.hidden, isTrue);
      expect(chrome.onScroll(3), ChromeAction.show);
      expect(chrome.hidden, isFalse);
      expect(chrome.onScroll(1), ChromeAction.show);
    });

    test('a second downward flick after hiding asks for nothing', () {
      final chrome = ChromeVisibility();
      chrome.onScroll(100);
      chrome.onScroll(200);
      expect(chrome.hidden, isTrue);
      expect(chrome.onScroll(400), ChromeAction.none, reason: 'already hidden');
    });
  });

  group('being held', () {
    test('a locked chrome refuses to hide but still follows the page', () {
      final chrome = ChromeVisibility()..lock();
      chrome.onScroll(100);
      expect(chrome.onScroll(400), ChromeAction.none);
      expect(chrome.hidden, isFalse);

      chrome.unlock();
      // The position is up to date, so the next gesture needs its own travel.
      expect(chrome.onScroll(430), ChromeAction.hide);
    });

    test('locking brings it back immediately: the field is being typed into', () {
      final chrome = ChromeVisibility();
      chrome.onScroll(100);
      chrome.onScroll(300);
      expect(chrome.hidden, isTrue);
      chrome.lock();
      expect(chrome.hidden, isFalse);
      expect(chrome.locked, isTrue);
    });

    test('a new page resets to shown', () {
      final chrome = ChromeVisibility();
      chrome.onScroll(100);
      chrome.onScroll(300);
      chrome.reset();
      expect(chrome.hidden, isFalse);
      expect(chrome.onScroll(500), ChromeAction.none, reason: 'baseline is the new page top');
    });

    test('show() without a scroll gesture lands on the next one', () {
      final chrome = ChromeVisibility();
      chrome.onScroll(100);
      chrome.onScroll(300);
      chrome.show();
      expect(chrome.hidden, isFalse);
      expect(chrome.onScroll(320), ChromeAction.none, reason: '20 is below the threshold again');
    });
  });
}
