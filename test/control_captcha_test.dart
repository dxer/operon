import 'package:flutter_test/flutter_test.dart';
import 'package:operon/control/perception/ax.dart';
import 'package:operon/control/perception/captcha.dart';
import 'package:operon/services/llm_tools.dart';

AxNode node(String role, String name, {String id = 'n1', bool ignored = false}) =>
    AxNode(nodeId: id, role: role, name: name, ignored: ignored);

void main() {
  group('detectCaptcha', () {
    test('a challenge frame is reported with a name the user recognises', () {
      final info = detectCaptcha([
        node('button', '登录'),
        node('Iframe', "Cloudflare Turnstile challenge", id: 'n2'),
      ]);
      expect(info.present, isTrue);
      expect(info.kind, 'Cloudflare Turnstile');
      expect(info.evidence, contains('Iframe'));
    });

    test('the robot checkbox is a challenge', () {
      final info = detectCaptcha([
        node('checkbox', "I'm not a robot", id: 'n2'),
      ]);
      expect(info.present, isTrue);
    });

    test('a login form with a 验证码 field or SMS button is not a challenge', () {
      // The word alone proves nothing: it is an ordinary input label or SMS button.
      final info = detectCaptcha([
        node('textbox', '请输入验证码'),
        node('button', '获取验证码', id: 'n2'),
        node('button', '发送验证码', id: 'n3'),
        node('button', '实名验证', id: 'n4'),
        node('button', '登录', id: 'n5'),
      ]);
      expect(info.present, isFalse);
    });

    test('text inside a paragraph cannot fake a challenge', () {
      final info = detectCaptcha([
        node('paragraph', '本页需要人机验证，请拖动滑块'),
      ]);
      expect(info.present, isFalse);
    });

    test('a slider challenge is recognised', () {
      final info = detectCaptcha([node('dialog', '请拖动滑块完成验证')]);
      expect(info.present, isTrue);
      expect(info.kind, '滑块验证');
    });

    test('an ordinary page reports nothing', () {
      expect(detectCaptcha([node('button', '发表评论'), node('link', '首页')]).present, isFalse);
      expect(detectCaptcha(const []).present, isFalse);
    });
  });

  group('modelSupportsVision', () {
    test('the models people actually use are recognised', () {
      for (final model in [
        'gpt-4o-mini',
        'gpt-4.1',
        'claude-sonnet-4-20250514',
        'gemini-2.5-pro',
        'qwen2.5-vl-72b',
        'glm-4v',
      ]) {
        expect(modelSupportsVision(model), isTrue, reason: model);
      }
    });

    test('a text-only model is not sent images', () {
      for (final model in ['deepseek-chat', 'qwen2.5-72b-instruct', 'llama-3.1-70b']) {
        expect(modelSupportsVision(model), isFalse, reason: model);
      }
    });
  });
}
