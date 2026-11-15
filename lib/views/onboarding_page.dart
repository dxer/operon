import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../config/app_tokens.dart';
import '../config/provider_presets.dart';
import '../models/llm_config.dart';
import '../services/goal_handoff.dart';
import '../services/haptic_service.dart';
import '../services/llm_service.dart';
import '../services/llm_tools.dart';
import '../services/model_probe.dart';
import '../services/storage_service.dart';
import 'widgets/operon_list_row.dart';

/// First run: what this browser does, which model will drive it, and one real
/// task to try.
///
/// The order is deliberate. The value comes before the API key: someone who
/// does not yet know why an agentic browser is different will not push through
/// a provider form to find out. The model check comes before the task, because
/// a task that fails on its first tool call teaches the wrong thing.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({
    super.key,
    required this.onDone,
    this.fetchModels,
    this.probe,
  });

  /// Called once the user finishes or skips. The caller owns what comes next.
  final VoidCallback onDone;

  /// Injected by tests. Production fetches the endpoint's own model list.
  final Future<List<String>> Function(LlmConfig config)? fetchModels;

  /// Injected by tests. Production sends the shared ping probe.
  final Future<ModelProbeResult> Function(LlmConfig config)? probe;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  static const int _lastStep = 2;

  late StorageService _storage;
  bool _loading = true;
  int _step = 0;
  bool _finishing = false;

  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  bool _obscureApiKey = true;

  bool _testing = false;
  bool _fetchingModels = false;
  List<String> _models = const [];
  String? _error;

  /// Set when the endpoint answered but the model did not call the probe tool.
  /// It is a warning, not a wall: the user may know their model better.
  ModelProbeResult? _probeResult;

  /// On a short phone the notices sit under the form. Scrolling to them is how
  /// a failed test says anything at all.
  final GlobalKey _noticeKey = GlobalKey();

  void _revealNotice() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notice = _noticeKey.currentContext;
      if (notice == null) return;
      Scrollable.ensureVisible(
        notice,
        duration: MediaQuery.maybeDisableAnimationsOf(context) == true
            ? Duration.zero
            : const Duration(milliseconds: 240),
        alignment: 0.88,
      );
    });
  }

  /// The provider whose base URL is in the field, for the selected chip and
  /// its setup note.
  ProviderPreset? get _matchedProvider {
    final url = _baseUrlController.text.trim();
    for (final preset in providerPresets) {
      if (preset.baseUrl == url) return preset;
    }
    return null;
  }

  LlmConfig get _currentConfig => LlmConfig(
        baseUrl: _baseUrlController.text.trim(),
        apiKey: _apiKeyController.text.trim(),
        model: _modelController.text.trim(),
        temperature: 0.1,
      );

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _storage = await StorageService.getInstance();
    final config = _storage.getLlmConfig();
    if (config.baseUrl.isNotEmpty) _baseUrlController.text = config.baseUrl;
    if (config.model.isNotEmpty) _modelController.text = config.model;
    if (config.apiKey.isNotEmpty) _apiKeyController.text = config.apiKey;
    if (mounted) setState(() => _loading = false);
  }

  void _clearCheck() {
    if (_error == null && _probeResult == null) return;
    setState(() {
      _error = null;
      _probeResult = null;
    });
  }

  void _onEndpointChanged() {
    // A list or a check belongs to one endpoint. Editing the URL retires both.
    if (_models.isEmpty) {
      _clearCheck();
      return;
    }
    setState(() {
      _models = const [];
      _error = null;
      _probeResult = null;
    });
  }

  void _applyProvider(ProviderPreset preset) {
    HapticService.selection();
    FocusScope.of(context).unfocus();
    final changingEndpoint =
        _baseUrlController.text.trim() != preset.baseUrl;
    if (changingEndpoint) _apiKeyController.clear();
    _baseUrlController.text = preset.baseUrl;
    _modelController.text = preset.model;
    setState(() {
      _models = const [];
      _error = null;
      _probeResult = null;
    });
  }

  Future<List<String>> _fetchModelsFrom(LlmConfig config) async {
    final service = LlmService();
    try {
      return await service.fetchModels(config);
    } finally {
      service.dispose();
    }
  }

  Future<void> _fetchModels() async {
    final config = _currentConfig;
    if (config.baseUrl.isEmpty) {
      setState(() => _error = '先填写 Base URL，才能获取模型列表。');
      _revealNotice();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _fetchingModels = true;
      _error = null;
    });
    try {
      final fetched = widget.fetchModels != null
          ? await widget.fetchModels!(config)
          : await _fetchModelsFrom(config);
      if (!mounted) return;
      final unique = <String>[];
      for (final model in fetched) {
        final name = model.trim();
        if (name.isNotEmpty && !unique.contains(name)) unique.add(name);
      }
      setState(() {
        _models = unique;
        _fetchingModels = false;
      });
      if (unique.isEmpty) {
        setState(() => _error = '这个端点没有返回任何模型，可以直接填写模型名。');
        _revealNotice();
      } else {
        await _showModelSheet();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _fetchingModels = false;
        _error = describeLlmFailure(error);
      });
      _revealNotice();
    }
  }

  Future<void> _showModelSheet() async {
    if (_models.isEmpty) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final surface = AppInk.raised(isDark);
        final hairline = AppInk.hairline(isDark);
        final current = _modelController.text.trim();
        return FractionallySizedBox(
          heightFactor: 0.66,
          child: Container(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadius.sheet),
              ),
              border: Border(
                top: BorderSide(color: hairline, width: AppStroke.hairline),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(
                        top: AppSpace.x2,
                        bottom: AppSpace.x1,
                      ),
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: hairline,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpace.page,
                      AppSpace.x2,
                      AppSpace.x2,
                      AppSpace.x2,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '选择模型 · ${_models.length}',
                            style: AppType.headline.copyWith(
                              color: AppInk.primary(isDark),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭',
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: AppStroke.hairline,
                    thickness: AppStroke.hairline,
                    color: hairline,
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpace.x1,
                      ),
                      itemCount: _models.length,
                      separatorBuilder: (_, __) => Divider(
                        height: AppStroke.hairline,
                        thickness: AppStroke.hairline,
                        indent: AppSpace.page,
                        endIndent: AppSpace.page,
                        color: hairline,
                      ),
                      itemBuilder: (_, index) {
                        final model = _models[index];
                        final selected = model == current;
                        return OperonListRow(
                          title: model,
                          showChevron: false,
                          minHeight: 48,
                          titleStyle: AppType.label.copyWith(
                            color: selected
                                ? AppTheme.primaryOf(isDark)
                                : AppInk.primary(isDark),
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w500,
                          ),
                          trailing: selected
                              ? Icon(
                                  Icons.check_rounded,
                                  size: 18,
                                  color: AppTheme.primaryOf(isDark),
                                )
                              : null,
                          onTap: () {
                            HapticService.selection();
                            Navigator.of(ctx).pop(model);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    _modelController.text = picked;
    _clearCheck();
    setState(() {});
  }

  /// The one thing the agent needs from a model: a tool call. A text reply
  /// alone is not enough, so success here means "this can drive a page".
  Future<void> _testAndContinue() async {
    final config = _currentConfig;
    if (!config.isValid) {
      setState(() => _error = '请填写完整的 Base URL、API Key 和模型名。');
      _revealNotice();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _testing = true;
      _error = null;
      _probeResult = null;
    });
    try {
      final result = widget.probe != null
          ? await widget.probe!(config)
          : await probeModel(
              config: config,
              profile: _storage.getModelProfile(config),
            );
      if (!mounted) return;
      if (result.calledTool) {
        await _storage.saveLlmConfig(config);
        if (!mounted) return;
        HapticService.light();
        setState(() {
          _testing = false;
          _step = _lastStep;
        });
      } else {
        setState(() {
          _testing = false;
          _probeResult = result;
        });
        _revealNotice();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _error = describeLlmFailure(error);
      });
      _revealNotice();
    }
  }

  /// For a model the user knows better than the probe: the endpoint works, it
  /// just answered in prose instead of calling the tool.
  Future<void> _continueDespiteWarning() async {
    await _storage.saveLlmConfig(_currentConfig);
    if (!mounted) return;
    setState(() {
      _probeResult = null;
      _step = _lastStep;
    });
  }

  void _back() {
    if (_step == 0) return;
    setState(() {
      _step -= 1;
      _error = null;
      _probeResult = null;
    });
  }

  Future<void> _finish({_StarterTask? task}) async {
    if (_finishing) return;
    setState(() => _finishing = true);
    await _storage.saveOnboardingDone();
    if (task != null) {
      GoalHandoff.send(goal: task.goal, url: task.url);
    }
    if (!mounted) return;
    widget.onDone();
  }

  void _startTask(_StarterTask task) {
    HapticService.selection();
    _finish(task: task);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return PopScope(
      // Back is "the previous step" while there is one. On the welcome step
      // the system may close the app, which is what back means there.
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step > 0) _back();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _buildTopBar(isDark),
              Expanded(
                child: AnimatedSwitcher(
                  duration:
                      MediaQuery.maybeDisableAnimationsOf(context) == true
                          ? Duration.zero
                          : const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.04, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(_step),
                    child: _buildStep(isDark),
                  ),
                ),
              ),
              _buildFooter(isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(bool isDark) {
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: _step > 0
                ? IconButton(
                    tooltip: '上一步',
                    icon: const Icon(Icons.arrow_back_rounded, size: 20),
                    onPressed: _back,
                  )
                : null,
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var index = 0; index <= _lastStep; index++)
                  AnimatedContainer(
                    duration: MediaQuery.maybeDisableAnimationsOf(context) ==
                            true
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: index == _step ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: index == _step
                          ? AppTheme.primaryOf(isDark)
                          : AppInk.hairline(isDark),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 56,
            child: _step == 0
                ? TextButton(
                    key: const Key('onboarding-skip'),
                    onPressed: _finishing ? null : () => _finish(),
                    child: Text(
                      '跳过',
                      style: AppType.label.copyWith(
                        color: AppInk.secondary(isDark),
                      ),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildStep(bool isDark) {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
        AppSpace.page,
        AppSpace.x2,
        AppSpace.page,
        AppSpace.x6,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: switch (_step) {
            0 => _buildWelcome(isDark),
            1 => _buildModelSetup(isDark),
            _ => _buildReady(isDark),
          },
        ),
      ),
    );
  }

  Widget _buildWelcome(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpace.x6),
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppInk.accentTint(isDark),
              borderRadius: BorderRadius.circular(AppRadius.sheet),
            ),
            child: Icon(
              Icons.ads_click_rounded,
              size: 34,
              color: AppTheme.primaryOf(isDark),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.x5),
        Text(
          'Operon',
          textAlign: TextAlign.center,
          style: AppType.display.copyWith(color: AppInk.primary(isDark)),
        ),
        const SizedBox(height: AppSpace.x1),
        Text(
          '不只是浏览，而是操控。',
          textAlign: TextAlign.center,
          style: AppType.body.copyWith(color: AppInk.secondary(isDark)),
        ),
        const SizedBox(height: AppSpace.x8),
        const _ValueRow(
          icon: Icons.visibility_outlined,
          title: '每一步都看得见',
          body: 'AI 在真实页面上点击和输入，落点有光标和描边，随时可以中止。',
        ),
        const SizedBox(height: AppSpace.x5),
        const _ValueRow(
          icon: Icons.verified_user_outlined,
          title: '关键动作你说了算',
          body: '提交、发布、删除前先问你；支付、密码和验证码永远由你自己完成。',
        ),
        const SizedBox(height: AppSpace.x5),
        const _ValueRow(
          icon: Icons.ios_share_rounded,
          title: '结果能带走',
          body: '表格、清单和总结可以导出 CSV、JSON 或 Markdown。',
        ),
      ],
    );
  }

  Widget _buildModelSetup(bool isDark) {
    final matched = _matchedProvider;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpace.x3),
        Text(
          '连接一个模型',
          style: AppType.title.copyWith(color: AppInk.primary(isDark)),
        ),
        const SizedBox(height: AppSpace.x2),
        Text(
          'Operon 不自带模型。填一个 OpenAI 兼容端点，浏览器才有大脑。',
          style: AppType.body.copyWith(color: AppInk.secondary(isDark)),
        ),
        const SizedBox(height: AppSpace.x6),
        Text(
          '常用服务商',
          style: AppType.label.copyWith(
            color: AppInk.primary(isDark),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpace.x2 + 2),
        Wrap(
          spacing: AppSpace.x2,
          runSpacing: AppSpace.x2,
          children: [
            for (final preset in providerPresets)
              _ProviderChip(
                label: preset.name,
                selected: matched?.name == preset.name,
                onTap: () => _applyProvider(preset),
              ),
          ],
        ),
        if (matched != null && matched.note.isNotEmpty) ...[
          const SizedBox(height: AppSpace.x3),
          _Notice(
            icon: Icons.info_outline_rounded,
            tone: AppTheme.warningOf(isDark),
            title: matched.name,
            message: matched.note,
          ),
        ],
        const SizedBox(height: AppSpace.x4),
        Container(
          padding: const EdgeInsets.all(AppSpace.x4),
          decoration: BoxDecoration(
            color: AppInk.raised(isDark),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: AppInk.hairline(isDark),
              width: AppStroke.hairline,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('onboarding-base-url'),
                controller: _baseUrlController,
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.none,
                style: AppType.body,
                decoration: const InputDecoration(
                  labelText: 'Base URL',
                  hintText: 'https://api.example.com/v1',
                  helperText: '末尾会自动补 /chat/completions',
                ),
                onChanged: (_) => _onEndpointChanged(),
              ),
              const SizedBox(height: AppSpace.x4),
              TextField(
                key: const Key('onboarding-api-key'),
                controller: _apiKeyController,
                obscureText: _obscureApiKey,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.none,
                style: AppType.body,
                decoration: InputDecoration(
                  labelText: 'API Key',
                  hintText: 'sk-...',
                  helperText: '只保存在本机，只发送给你填写的端点',
                  suffixIcon: IconButton(
                    tooltip: _obscureApiKey ? '显示密钥' : '隐藏密钥',
                    icon: Icon(
                      _obscureApiKey
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _obscureApiKey = !_obscureApiKey),
                  ),
                ),
                onChanged: (_) => _clearCheck(),
              ),
              const SizedBox(height: AppSpace.x4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('onboarding-model'),
                      controller: _modelController,
                      autocorrect: false,
                      enableSuggestions: false,
                      textCapitalization: TextCapitalization.none,
                      style: AppType.body,
                      decoration: const InputDecoration(
                        labelText: '模型',
                        hintText: '点右侧获取，或直接填写',
                      ),
                      onChanged: (_) => _clearCheck(),
                      onSubmitted: (_) => _testAndContinue(),
                    ),
                  ),
                  const SizedBox(width: AppSpace.x2),
                  OutlinedButton(
                    onPressed: _fetchingModels
                        ? null
                        : (_models.isEmpty ? _fetchModels : _showModelSheet),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 54),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.x3,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                      ),
                    ),
                    child: _fetchingModels
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _models.isEmpty ? '获取列表' : '选择 (${_models.length})',
                            style: AppType.caption,
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.x3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 16,
              color: AppInk.tertiary(isDark),
            ),
            const SizedBox(width: AppSpace.x2),
            Expanded(
              child: Text(
                '密钥不会经过 Operon 的服务器。本地模型不校验密钥时，可填任意字符。',
                style: AppType.caption.copyWith(color: AppInk.tertiary(isDark)),
              ),
            ),
          ],
        ),
        KeyedSubtree(
          key: _noticeKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                const SizedBox(height: AppSpace.x4),
                _Notice(
                  icon: Icons.error_outline_rounded,
                  tone: AppTheme.dangerOf(isDark),
                  title: '连接失败',
                  message: _error!,
                ),
              ],
              if (_probeResult != null && !_probeResult!.calledTool) ...[
                const SizedBox(height: AppSpace.x4),
                _Notice(
                  icon: Icons.warning_amber_rounded,
                  tone: AppTheme.warningOf(isDark),
                  title: '能连通，但模型没有调用工具',
                  message:
                      'Operon 依靠 function calling 操作网页。换一个支持工具调用的模型最稳妥；'
                      '如果你确定这个模型可用，也可以继续。\n\n'
                      '模型回复：${(_probeResult!.content ?? '').trim().isEmpty ? '（空）' : _probeResult!.content}',
                  action: TextButton(
                    onPressed: _continueDespiteWarning,
                    child: const Text('仍然继续'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReady(bool isDark) {
    final model = _modelController.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpace.x3),
        Text(
          '准备好了',
          style: AppType.title.copyWith(color: AppInk.primary(isDark)),
        ),
        const SizedBox(height: AppSpace.x2),
        Text(
          '选一个任务试试。进入后它会先填进输入框，由你确认发送。',
          style: AppType.body.copyWith(color: AppInk.secondary(isDark)),
        ),
        if (model.isNotEmpty) ...[
          const SizedBox(height: AppSpace.x2),
          Text(
            '当前模型 · $model',
            style: AppType.caption.copyWith(color: AppInk.tertiary(isDark)),
          ),
        ],
        const SizedBox(height: AppSpace.x6),
        for (var index = 0; index < _starterTasks.length; index++) ...[
          if (index > 0) const SizedBox(height: AppSpace.x3),
          _TaskCard(
            key: Key('onboarding-example-$index'),
            task: _starterTasks[index],
            onTap: () => _startTask(_starterTasks[index]),
          ),
        ],
        const SizedBox(height: AppSpace.x5),
        Text(
          '任务由你的模型执行，可能产生少量 API 费用。随时可以停止。',
          textAlign: TextAlign.center,
          style: AppType.caption.copyWith(color: AppInk.tertiary(isDark)),
        ),
      ],
    );
  }

  Widget _buildFooter(bool isDark) {
    final label = switch (_step) {
      0 => '开始设置',
      1 => '测试并继续',
      _ => '进入浏览器',
    };
    final VoidCallback? onPressed = switch (_step) {
      0 => () => setState(() => _step = 1),
      1 => _testing ? null : () => _testAndContinue(),
      _ => _finishing ? null : () => _finish(),
    };

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkBg : AppTheme.lightBg,
        border: Border(
          top: BorderSide(
            color: AppInk.hairline(isDark),
            width: AppStroke.hairline,
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpace.page,
        AppSpace.x3,
        AppSpace.page,
        AppSpace.x3,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: AppSpace.pill,
                child: FilledButton(
                  key: const Key('onboarding-primary'),
                  onPressed: onPressed,
                  style: FilledButton.styleFrom(
                    textStyle: AppType.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                  ),
                  child: _testing
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Theme.of(context).colorScheme.onPrimary,
                              ),
                            ),
                            const SizedBox(width: AppSpace.x2),
                            const Text('正在测试…'),
                          ],
                        )
                      : Text(label),
                ),
              ),
              if (_step == 1)
                TextButton(
                  onPressed: _testing ? null : () => _finish(),
                  child: Text(
                    '稍后设置',
                    style: AppType.label.copyWith(
                      color: AppInk.secondary(isDark),
                    ),
                  ),
                )
              else if (_step == 0)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.x2),
                  child: Text(
                    '需要一个大模型端点 · 密钥只保存在本机',
                    textAlign: TextAlign.center,
                    style: AppType.caption.copyWith(
                      color: AppInk.tertiary(isDark),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StarterTask {
  const _StarterTask({
    required this.icon,
    required this.title,
    required this.goal,
    required this.url,
  });

  final IconData icon;
  final String title;
  final String goal;
  final String url;
}

const List<_StarterTask> _starterTasks = [
  _StarterTask(
    icon: Icons.travel_explore_rounded,
    title: '搜索并总结',
    goal: '打开 Bing 搜索「Flutter 3.35 发布说明」，打开第一条结果，总结更新要点',
    url: 'https://www.bing.com',
  ),
  _StarterTask(
    icon: Icons.table_chart_outlined,
    title: '网页转表格',
    goal: '打开 GitHub Trending，把前 5 个项目整理成表格，包含项目名、语言和今日新增 star',
    url: 'https://github.com/trending',
  ),
  _StarterTask(
    icon: Icons.tips_and_updates_outlined,
    title: '填表查资料',
    goal: '打开维基百科，搜索「Alan Turing」，告诉我他的出生日期和主要贡献',
    url: 'https://zh.wikipedia.org',
  ),
];

class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppInk.accentTint(isDark),
            borderRadius: BorderRadius.circular(AppRadius.icon),
          ),
          child: Icon(icon, size: 18, color: AppTheme.primaryOf(isDark)),
        ),
        const SizedBox(width: AppSpace.x3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppType.label.copyWith(
                  color: AppInk.primary(isDark),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpace.x1),
              Text(
                body,
                style: AppType.body.copyWith(
                  color: AppInk.secondary(isDark),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProviderChip extends StatelessWidget {
  const _ProviderChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppTheme.primaryOf(isDark);
    final border = selected ? accent : AppInk.hairline(isDark);
    return Material(
      color: selected ? AppInk.accentTint(isDark) : AppInk.raised(isDark),
      shape: StadiumBorder(
        side: BorderSide(color: border, width: AppStroke.hairline),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.x3,
            vertical: AppSpace.x2,
          ),
          child: Text(
            label,
            style: AppType.label.copyWith(
              color: selected ? accent : AppInk.secondary(isDark),
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.tone,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final Color tone;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(AppSpace.x3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: isDark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(
          color: tone.withValues(alpha: 0.35),
          width: AppStroke.hairline,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: tone),
          const SizedBox(width: AppSpace.x2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppType.label.copyWith(
                    color: tone,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpace.x1),
                Text(
                  message,
                  style: AppType.label.copyWith(
                    color: AppInk.secondary(isDark),
                    fontWeight: FontWeight.w400,
                  ),
                ),
                if (action != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpace.x1),
                    child: action!,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({super.key, required this.task, required this.onTap});

  final _StarterTask task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: AppInk.raised(isDark),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(
          color: AppInk.hairline(isDark),
          width: AppStroke.hairline,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.x4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppInk.accentTint(isDark),
                  borderRadius: BorderRadius.circular(AppRadius.icon),
                ),
                child: Icon(
                  task.icon,
                  size: 18,
                  color: AppTheme.primaryOf(isDark),
                ),
              ),
              const SizedBox(width: AppSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: AppType.label.copyWith(
                        color: AppInk.primary(isDark),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpace.x1),
                    Text(
                      task.goal,
                      style: AppType.body.copyWith(
                        color: AppInk.secondary(isDark),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.x2),
              Icon(
                Icons.arrow_outward_rounded,
                size: 18,
                color: AppInk.tertiary(isDark),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
