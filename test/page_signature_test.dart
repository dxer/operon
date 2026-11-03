import 'package:flutter_test/flutter_test.dart';
import 'package:operon/models/page_signature.dart';

const _base = PageSignature(
  url: 'https://example.com',
  title: 'Example',
  elementCount: 10,
  textLength: 100,
  scrollHeight: 1000,
);

void main() {
  test('identical signatures do not report a change', () {
    expect(_base.changedFrom(_base), isFalse);
    expect(
      _base.changedFrom(const PageSignature(
        url: 'https://example.com',
        title: 'Example',
        elementCount: 10,
        textLength: 100,
        scrollHeight: 1000,
      )),
      isFalse,
    );
  });

  test('each field participates in the comparison', () {
    expect(
      _base.changedFrom(const PageSignature(
        url: 'https://example.com/next',
        title: 'Example',
        elementCount: 10,
        textLength: 100,
        scrollHeight: 1000,
      )),
      isTrue,
    );
    expect(
      _base.changedFrom(const PageSignature(
        url: 'https://example.com',
        title: 'Example 2',
        elementCount: 10,
        textLength: 100,
        scrollHeight: 1000,
      )),
      isTrue,
    );
    expect(
      _base.changedFrom(const PageSignature(
        url: 'https://example.com',
        title: 'Example',
        elementCount: 11,
        textLength: 100,
        scrollHeight: 1000,
      )),
      isTrue,
    );
    expect(
      _base.changedFrom(const PageSignature(
        url: 'https://example.com',
        title: 'Example',
        elementCount: 10,
        textLength: 101,
        scrollHeight: 1000,
      )),
      isTrue,
    );
    expect(
      _base.changedFrom(const PageSignature(
        url: 'https://example.com',
        title: 'Example',
        elementCount: 10,
        textLength: 100,
        scrollHeight: 1001,
      )),
      isTrue,
    );
  });

  test('fromJson tolerates missing fields', () {
    final signature = PageSignature.fromJson(const {'url': 'https://a.test'});
    expect(signature.url, 'https://a.test');
    expect(signature.title, '');
    expect(signature.elementCount, 0);
    expect(signature.valid, isTrue);
    expect(PageSignature.fromJson(const {}).valid, isFalse);
  });
}
