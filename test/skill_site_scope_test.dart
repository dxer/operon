import 'package:flutter_test/flutter_test.dart';
import 'package:operon/models/skill.dart';

Skill _skill(SkillPolicy policy) => Skill(
      id: 's',
      name: 'S',
      instructions: 'do it',
      policy: policy,
    );

void main() {
  test('unscoped skills can run anywhere', () {
    final skill = _skill(const SkillPolicy());
    expect(skill.allowsHost('example.com'), isTrue);
    expect(skill.matchesHost('example.com'), isFalse);
  });

  test('exact hosts are matched after normalization', () {
    final skill = _skill(const SkillPolicy(
      hostScope: SkillHostScope.list,
      allowedHosts: ['x.com'],
    ));
    expect(skill.allowsHost('www.x.com'), isTrue);
    expect(skill.allowsHost('X.COM'), isTrue);
    expect(skill.allowsHost('example.com'), isFalse);
    expect(skill.matchesHost('x.com'), isTrue);
  });

  test('wildcard subdomains are allowed', () {
    final skill = _skill(const SkillPolicy(
      hostScope: SkillHostScope.list,
      allowedHosts: ['*.example.com'],
    ));
    expect(skill.allowsHost('a.example.com'), isTrue);
    expect(skill.allowsHost('example.com'), isTrue);
    expect(skill.allowsHost('notexample.com'), isFalse);
  });

  test('a currentHost scope with no recorded host is not a restriction', () {
    final skill = _skill(const SkillPolicy(
      hostScope: SkillHostScope.currentHost,
    ));
    expect(skill.allowsHost('anything.test'), isTrue);
  });

  test('currentHost scope keeps a run on the page it started from', () {
    final skill = _skill(const SkillPolicy(
      hostScope: SkillHostScope.currentHost,
    ));
    expect(skill.allowsHostAt('x.com', startHost: 'x.com'), isTrue);
    expect(skill.allowsHostAt('www.x.com', startHost: 'x.com'), isTrue);
    expect(skill.allowsHostAt('evil.test', startHost: 'x.com'), isFalse);
    // Before the first page is known there is no rule to apply.
    expect(skill.allowsHostAt('evil.test'), isTrue);
  });

  test('recorded hosts are a hard list even for currentHost scope', () {
    final skill = _skill(const SkillPolicy(
      hostScope: SkillHostScope.currentHost,
      allowedHosts: ['x.com'],
    ));
    expect(skill.allowsHostAt('x.com', startHost: 'x.com'), isTrue);
    expect(skill.allowsHostAt('evil.test', startHost: 'x.com'), isFalse);
    // A run that somehow starts on another site is refused up front.
    expect(skill.allowsHostAt('evil.test', startHost: 'evil.test'), isFalse);
  });
}
