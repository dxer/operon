import '../config/skill_creator_prompt.dart';
import '../config/tool_catalog.dart';
import '../models/agent_state.dart';
import '../models/llm_config.dart';
import '../models/skill.dart';
import '../utils/cancellation.dart';
import '../utils/url_utils.dart';
import 'agent_runner.dart';
import 'skill_authoring_service.dart';
import 'skill_recording_session.dart';
import 'skill_validator.dart';
import 'webview_controller_wrapper.dart';

/// Creates a flow skill by driving the real page once and recording the
/// element anchors the agent actually used.
///
/// The terminal write (publish/send/submit) is never dispatched: it is
/// resolved and recorded, then the demonstration ends. This makes skill
/// creation safe even when the target site has no sandbox.
class SkillCreatorService {
  const SkillCreatorService();

  Future<SkillAuthoringResult> create({
    required String description,
    required LlmConfig config,
    required WebViewControllerWrapper webView,
    String sampleContent = '',
    int maxSteps = 30,
    CancellationToken? token,
    void Function(String stage)? onProgress,
  }) async {
    final text = description.trim();
    if (text.isEmpty) {
      return const SkillAuthoringResult(error: '请先描述你想让技能做什么');
    }
    if (!config.isValid) {
      return const SkillAuthoringResult(
        error: '请先在设置中配置有效的大模型 API Key',
      );
    }
    if (token?.isCancelled == true) {
      return const SkillAuthoringResult(error: '生成已取消');
    }

    String url;
    try {
      url = await webView.getUrl();
    } catch (e) {
      return SkillAuthoringResult(error: '无法读取当前页面地址：$e');
    }
    final host = hostOf(url);
    if (host.isEmpty ||
        url.startsWith('about:') ||
        url.startsWith('operon://')) {
      return const SkillAuthoringResult(
        error: '请先在浏览器中打开目标网站，再创建演示技能',
      );
    }

    onProgress?.call('正在准备演示…');
    final session = SkillRecordingSession(
      sampleContent: sampleContent,
      currentHost: host,
    );
    final runner = AgentRunner();
    var cancelled = false;
    var captchaHandled = false;
    AgentState lastState = runner.state;

    token?.whenCancelled.then((_) {
      cancelled = true;
      runner.stop();
    });

    final subscription = runner.stateStream.listen((state) {
      lastState = state;
      if (state.status == AgentStatus.waitingCaptcha && !captchaHandled) {
        captchaHandled = true;
        onProgress?.call('检测到人机验证，请先在浏览器完成验证后重试');
        // This sheet is modal, so the user cannot solve the challenge behind
        // it. Fail fast with a clear reason instead of waiting five minutes.
        Future<void>.delayed(const Duration(seconds: 2), () {
          if (lastState.status == AgentStatus.waitingCaptcha) {
            runner.confirmCaptchaSolved(false);
            runner.stop();
          }
        });
      } else if (state.status == AgentStatus.waitingConfirmation) {
        // Creator mode has no confirmation UI and must fail closed.
        runner.confirmAction(false);
      } else if (state.logs.isNotEmpty) {
        onProgress?.call(state.logs.last.title);
      }
    });

    try {
      await runner.run(
        userGoal: SkillCreatorPrompt.goal(description: text, host: host),
        webView: webView,
        config: config,
        maxSteps: maxSteps,
        safeMode: false,
        policy: SkillPolicy(
          maxSteps: maxSteps,
          maxSideEffects: 1,
          maxItems: 1,
          maxDurationMs: 600000,
          confirmWrites: false,
          confirmDestructive: false,
        ),
        recorder: session,
        extraSystemRules: SkillCreatorPrompt.rules(
          sampleContent: sampleContent,
          host: host,
        ),
        notifyOnComplete: false,
      );
    } catch (e) {
      return SkillAuthoringResult(error: '技能演示失败：$e');
    } finally {
      lastState = runner.state;
      await subscription.cancel();
      runner.dispose();
    }

    if (cancelled || token?.isCancelled == true) {
      return const SkillAuthoringResult(error: '生成已取消');
    }
    if (captchaHandled || lastState.status == AgentStatus.waitingCaptcha) {
      return const SkillAuthoringResult(
        error: '页面需要人机验证。请先在浏览器中完成验证，再重新创建技能。',
      );
    }
    if (lastState.status == AgentStatus.error) {
      return SkillAuthoringResult(
        error: lastState.errorMessage ?? '技能演示失败',
        raw: session.summary(),
      );
    }
    if (lastState.status == AgentStatus.idle) {
      return SkillAuthoringResult(
        error: '技能演示已停止，没有得到完整流程。',
        raw: session.summary(),
      );
    }
    if (session.stepCount == 0) {
      return SkillAuthoringResult(
        error: '没有得到可执行的步骤。请确认页面已打开、已登录，然后重试。',
        raw: session.summary(),
      );
    }

    var draft = session.buildDraft(
      name: SkillRecordingSession.deriveName(text),
      description: text,
    );
    if (draft == null) {
      return SkillAuthoringResult(
        error: '没有得到可执行的步骤。',
        raw: session.summary(),
      );
    }
    if (lastState.status == AgentStatus.maxStepsReached) {
      draft = draft.copyWith(
        notes: '${draft.notes}\n已达到录制步数上限，请检查流程是否完整。',
      );
    }

    final validation = SkillValidator().validateDraft(
      draft,
      allowWrites: true,
      currentHost: host,
      restrictToCurrentHost: true,
      allowedToolIds: ToolCatalog.authoringIds,
    );
    if (validation.hasErrors) {
      return SkillAuthoringResult(
        draft: draft,
        validation: validation,
        error: '录制完成，但技能草案还有校验问题，请手动调整。',
        raw: session.summary(),
        attempts: session.stepCount,
      );
    }

    return SkillAuthoringResult(
      draft: draft,
      validation: validation,
      raw: session.summary(),
      attempts: session.stepCount,
    );
  }
}
