import 'package:flutter_test/flutter_test.dart';
import 'package:operon/utils/url_utils.dart';

void main() {
  test('hostOf lowercases and strips a leading www.', () {
    expect(hostOf('https://WWW.Example.com/path?q=1'), 'example.com');
    expect(hostOf('http://sub.example.com'), 'sub.example.com');
    expect(hostOf('https://www2.example.com'), 'www2.example.com');
  });

  test('hostOf tolerates empty and invalid urls', () {
    expect(hostOf(''), '');
    expect(hostOf('not a url'), '');
  });

  test('normalizeHost trims and only strips the leading www.', () {
    expect(normalizeHost(' WWW.Example.com '), 'example.com');
    expect(normalizeHost('example.com'), 'example.com');
  });

  test('extractSharedUrl finds the first link in shared text', () {
    expect(
      extractSharedUrl('一篇好文章 https://example.com/a?b=1 推荐'),
      'https://example.com/a?b=1',
    );
    expect(
      extractSharedUrl('https://example.com/a。'),
      'https://example.com/a',
    );
    expect(
      extractSharedUrl('(see https://example.com/a)'),
      'https://example.com/a',
    );
    expect(extractSharedUrl('HTTPS://EXAMPLE.COM/X'), 'HTTPS://EXAMPLE.COM/X');
  });

  test('extractSharedUrl ignores text without a usable link', () {
    expect(extractSharedUrl(''), isNull);
    expect(extractSharedUrl('只有一段文字，没有链接'), isNull);
    expect(extractSharedUrl('https://'), isNull);
  });

  test('compactHost shortens long hosts to the registrable domain', () {
    expect(compactHost('example.com'), 'example.com');
    expect(
      compactHost('very-long-subdomain.example.co.uk'),
      'example.co.uk',
    );
    expect(compactHost('a.b.c.d.example.com'), 'example.com');
    // IP addresses and IPv6 literals are never split.
    expect(compactHost('192.168.100.200'), '192.168.100.200');
    expect(compactHost('2001:db8::1'), '2001:db8::1');
  });
}
