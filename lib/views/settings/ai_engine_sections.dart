part of 'ai_engine_settings_page.dart';

final List<({String name, String url})> _endpointPresets = [
  for (final preset in providerPresets)
    (name: preset.name, url: preset.baseUrl),
];

const List<int?> _quickMaxTokens = [null, 2048, 4096, 8192, 16384, 32768];
const List<int> _quickContextWindows = [
  8000,
  32000,
  64000,
  128000,
  200000,
  1000000,
];

extension _AiEngineSections on _AiEngineSettingsPageState {
  ButtonStyle _matchedFieldButtonStyle(
    bool isDark, {
    Color? foreground,
    EdgeInsetsGeometry padding =
        const EdgeInsets.symmetric(horizontal: AppSpace.x3 + 2),
    Size minimumSize = const Size(48, 48),
  }) {
    final border = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    return OutlinedButton.styleFrom(
      foregroundColor: foreground ?? AppTheme.primaryOf(isDark),
      backgroundColor: isDark ? AppTheme.darkInput : AppTheme.lightInput,
      side: BorderSide(color: border),
      padding: padding,
      minimumSize: minimumSize,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _sectionLabel(String text, bool isDark) => Text(
        text,
        style: AppType.label.copyWith(
          color: AppInk.primary(isDark),
          fontWeight: FontWeight.w600,
        ),
      );

  /// Three-way picker row: the user's answer, or "you decide".
  Widget _traitDropdown({
    required String label,
    required ModelTrait value,
    required String autoLabel,
    required ValueChanged<ModelTrait> onChanged,
  }) {
    final labels = {
      ModelTrait.auto: autoLabel,
      ModelTrait.yes: '支持',
      ModelTrait.no: '不支持',
    };
    return OperonOptionRow<ModelTrait>(
      key: ValueKey('${label}_${value.name}_$_profileFor'),
      title: label,
      padding: EdgeInsets.zero,
      value: value,
      options: [
        for (final trait in ModelTrait.values)
          OperonOptionItem<ModelTrait>(
            value: trait,
            label: labels[trait]!,
          ),
      ],
      onChanged: onChanged,
    );
  }

  String _formatContextWindowLabel(int tokens) {
    if (tokens >= 1000000 && tokens % 1000000 == 0) {
      return '${tokens ~/ 1000000}M ($tokens)';
    }
    if (tokens >= 1000 && tokens % 1000 == 0) {
      return '${tokens ~/ 1000}K ($tokens)';
    }
    return '$tokens';
  }

  Widget _buildPresetsCard({
    required bool isDark,
    required Color cardColor,
    required Color hairline,
    required LlmPreset? activePreset,
  }) {
    return OperonCard(
      color: cardColor,
      borderColor: hairline,
      radius: AppRadius.card,
      padding: const EdgeInsets.all(AppSpace.page),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '配置预设',
            style: AppType.label.copyWith(
              fontWeight: FontWeight.w600,
              color: AppInk.primary(isDark),
            ),
          ),
          const SizedBox(height: AppSpace.x3),
          if (_presets.isEmpty)
            Row(
              children: [
                Expanded(
                  child: Text(
                    '把常用的模型（如 DeepSeek、GPT、本地 Ollama）存成预设，切换时不用重新粘贴地址和密钥。',
                    style: AppType.caption.copyWith(
                      color: AppInk.secondary(isDark),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpace.x3),
                OutlinedButton.icon(
                  onPressed: _saveCurrentAsPreset,
                  icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                  label: const Text('存为预设', style: AppType.caption),
                  style: _matchedFieldButtonStyle(
                    isDark,
                    minimumSize: const Size(0, 40),
                  ),
                ),
              ],
            )
          else
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(
                        'preset_${activePreset?.id}_${_presets.length}',
                      ),
                      initialValue: activePreset?.id,
                      isExpanded: true,
                      menuMaxHeight: 280,
                      hint: Text(
                        '选择预设 (${_presets.length})',
                        style: AppType.label.copyWith(
                          color: AppInk.tertiary(isDark),
                        ),
                      ),
                      decoration: InputDecoration(
                        labelText: '快速切换预设 (${_presets.length})',
                      ),
                      items: [
                        for (final preset in _presets)
                          DropdownMenuItem<String>(
                            value: preset.id,
                            child: Text(
                              preset.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.label,
                            ),
                          ),
                      ],
                      onChanged: (presetId) {
                        if (presetId == null) return;
                        final picked = _presets
                            .where((item) => item.id == presetId)
                            .firstOrNull;
                        if (picked != null) _applyPreset(picked);
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpace.x2),
                  Tooltip(
                    message: '存为新预设',
                    child: OutlinedButton(
                      onPressed: _saveCurrentAsPreset,
                      style: _matchedFieldButtonStyle(
                        isDark,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(48, 48),
                      ),
                      child: const Icon(
                        Icons.bookmark_add_outlined,
                        size: 18,
                      ),
                    ),
                  ),
                  if (activePreset != null) ...[
                    const SizedBox(width: AppSpace.x2),
                    Tooltip(
                      message: '删除当前预设',
                      child: OutlinedButton(
                        onPressed: () => _deletePreset(activePreset),
                        style: _matchedFieldButtonStyle(
                          isDark,
                          foreground: AppTheme.dangerOf(isDark),
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(48, 48),
                        ),
                        child: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEndpointConfigCard({
    required bool isDark,
    required Color cardColor,
    required Color hairline,
    required List<String> uniqueModels,
    required String? matchedModel,
  }) {
    return OperonCard(
      color: cardColor,
      borderColor: hairline,
      radius: AppRadius.card,
      padding: const EdgeInsets.all(AppSpace.page),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'OpenAI 兼容端点配置',
            style: AppType.label.copyWith(
              fontWeight: FontWeight.w600,
              color: AppInk.primary(isDark),
            ),
          ),
          const SizedBox(height: AppSpace.x3 + 2),
          TextField(
            controller: _baseUrlController,
            style: AppType.label.copyWith(fontSize: 13.5),
            decoration: InputDecoration(
              labelText: 'Base URL',
              hintText: 'https://api.example.com/v1',
              helperText: '任意 OpenAI 兼容端点，末尾会自动补 /chat/completions',
              suffixIcon: PopupMenuButton<String>(
                tooltip: '选择常用端点',
                icon: const Icon(Icons.arrow_drop_down_rounded),
                onSelected: (url) {
                  _mutate(() => _baseUrlController.text = url);
                  _schedulePersist();
                  _reloadProfileIfModelChanged();
                },
                itemBuilder: (_) => [
                  for (final preset in _endpointPresets)
                    PopupMenuItem<String>(
                      value: preset.url,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(preset.name, style: AppType.label),
                          Text(
                            preset.url,
                            style: AppType.micro.copyWith(
                              color: AppInk.tertiary(isDark),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            onChanged: (_) {
              _schedulePersist();
              _reloadProfileIfModelChanged();
            },
          ),
          const SizedBox(height: AppSpace.x3 + 2),
          TextField(
            controller: _apiKeyController,
            obscureText: _obscureApiKey,
            style: AppType.label.copyWith(fontSize: 13.5),
            decoration: InputDecoration(
              labelText: 'API Key',
              hintText: 'sk-...',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureApiKey
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                ),
                onPressed: () => _mutate(() => _obscureApiKey = !_obscureApiKey),
              ),
            ),
            onChanged: (_) => _schedulePersist(),
          ),
          const SizedBox(height: AppSpace.x3 + 2),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: TextField(
                    controller: _modelController,
                    style: AppType.label.copyWith(fontSize: 13.5),
                    decoration: const InputDecoration(
                      labelText: 'Model 模型名',
                      hintText: '点右侧获取，或直接填写',
                    ),
                    onChanged: (_) {
                      _schedulePersist();
                      _reloadProfileIfModelChanged();
                    },
                  ),
                ),
                const SizedBox(width: AppSpace.x2),
                OutlinedButton(
                  onPressed: _isLoadingModels ? null : _fetchModels,
                  style: _matchedFieldButtonStyle(
                    isDark,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.x3,
                    ),
                  ),
                  child: _isLoadingModels
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('获取列表', style: AppType.caption),
                ),
              ],
            ),
          ),
          if (uniqueModels.isNotEmpty) ...[
            const SizedBox(height: AppSpace.x3),
            DropdownButtonFormField<String>(
              key: ValueKey(
                'models_${_modelsFor}_${matchedModel}_${uniqueModels.length}',
              ),
              initialValue: matchedModel,
              isExpanded: true,
              menuMaxHeight: 320,
              hint: Text(
                '从列表中选择可用模型',
                style: AppType.label.copyWith(
                  color: AppInk.tertiary(isDark),
                ),
              ),
              decoration: InputDecoration(
                labelText: '可用模型 (${uniqueModels.length})',
              ),
              items: [
                for (final model in uniqueModels)
                  DropdownMenuItem<String>(
                    value: model,
                    child: Text(
                      model,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.label,
                    ),
                  ),
              ],
              onChanged: (model) {
                if (model == null) return;
                _mutate(() => _modelController.text = model);
                _persist();
                _reloadProfileIfModelChanged();
              },
            ),
          ],
          const SizedBox(height: AppSpace.x2),
          OperonOptionRow<ThinkingLevel>(
            key: ValueKey('thinking_${_thinking.name}'),
            title: '思考级别',
            subtitle: _thinking.description,
            padding: EdgeInsets.zero,
            value: _thinking,
            options: [
              for (final level in ThinkingLevel.values)
                OperonOptionItem<ThinkingLevel>(
                  value: level,
                  label: level.label,
                  subtitle: level.description,
                ),
            ],
            onChanged: (level) {
              _mutate(() => _thinking = level);
              _persist();
            },
          ),
          const SizedBox(height: AppSpace.x2),
          TextField(
            controller: _maxTokensController,
            style: AppType.label.copyWith(fontSize: 13.5),
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: '最大输出 token（可留空）',
              hintText: '留空则交给模型自己决定',
              suffixIcon: PopupMenuButton<int>(
                tooltip: '选择常用输出上限',
                icon: const Icon(Icons.arrow_drop_down_rounded),
                onSelected: (value) {
                  _mutate(() {
                    _maxTokensController.text = value <= 0 ? '' : '$value';
                  });
                  _persist();
                },
                itemBuilder: (_) => [
                  for (final tokens in _quickMaxTokens)
                    PopupMenuItem<int>(
                      value: tokens ?? -1,
                      child: Text(
                        tokens == null ? '留空（由模型自己决定）' : '$tokens',
                        style: AppType.label,
                      ),
                    ),
                ],
              ),
            ),
            onChanged: (_) => _schedulePersist(),
          ),
          const SizedBox(height: AppSpace.x4),
          ..._buildCapabilitiesSection(isDark),
        ],
      ),
    );
  }

  List<Widget> _buildCapabilitiesSection(bool isDark) {
    return [
      _sectionLabel('模型能力', isDark),
      const SizedBox(height: AppSpace.x1),
      Text(
        '未填写时默认上下文 200K，视觉按模型名识别。',
        style: AppType.micro.copyWith(
          color: AppInk.tertiary(isDark),
        ),
      ),
      const SizedBox(height: AppSpace.x3),
      TextField(
        controller: _contextWindowController,
        style: AppType.label.copyWith(fontSize: 13.5),
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: '上下文窗口（token）',
          hintText: '${ModelProfile.defaultContextWindow}',
          helperText: '模型一次能读多少个 token',
          suffixIcon: PopupMenuButton<int>(
            tooltip: '选择常用上下文档位',
            icon: const Icon(Icons.arrow_drop_down_rounded),
            onSelected: (value) {
              _contextWindowController.text = '$value';
              _saveProfile(_profile.copyWith(contextWindow: value));
            },
            itemBuilder: (_) => [
              for (final tokens in _quickContextWindows)
                PopupMenuItem<int>(
                  value: tokens,
                  child: Text(
                    _formatContextWindowLabel(tokens),
                    style: AppType.label,
                  ),
                ),
            ],
          ),
        ),
        onChanged: (text) {
          final value = int.tryParse(text.trim());
          if (value == null || value < 1000) return;
          _saveProfile(_profile.copyWith(contextWindow: value));
        },
      ),
      const SizedBox(height: AppSpace.x2),
      _traitDropdown(
        label: '图片输入',
        value: _profile.vision,
        autoLabel: '按模型名猜',
        onChanged: (trait) => _saveProfile(_profile.copyWith(vision: trait)),
      ),
      Divider(
        height: 1,
        thickness: AppStroke.hairline,
        color: AppInk.hairline(isDark),
      ),
      _traitDropdown(
        label: '思考参数',
        value: _profile.reasoning,
        autoLabel: '先试，被拒再退',
        onChanged: (trait) => _saveProfile(_profile.copyWith(reasoning: trait)),
      ),
      Divider(
        height: 1,
        thickness: AppStroke.hairline,
        color: AppInk.hairline(isDark),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        value: _profile.supportsTools,
        title: const Text(
          '支持工具调用',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          '关掉后智能体不会用这个模型跑任务',
          style: AppType.micro.copyWith(
            color: AppInk.tertiary(isDark),
          ),
        ),
        onChanged: (value) =>
            _saveProfile(_profile.copyWith(supportsTools: value)),
      ),
      const SizedBox(height: AppSpace.x2),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        value: _autoCompactEnabled,
        title: const Text(
          '自动压缩上下文（Auto-Compact）',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          '上下文达到下方阈值时自动摘要历史，也可随时发送 /compact 手动压缩',
          style: AppType.micro.copyWith(
            color: AppInk.tertiary(isDark),
          ),
        ),
        onChanged: _saveAutoCompactEnabled,
      ),
      const SizedBox(height: AppSpace.x2),
      TextField(
        controller: _autoCompactController,
        enabled: _autoCompactEnabled,
        style: AppType.label.copyWith(fontSize: 13.5),
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: 'Auto-Compact 触发阈值（token）',
          hintText: '${AppConstants.defaultAutoCompactTokens}',
          helperText: '默认 200K；达到该大小时自动触发压缩，避免超长对话溢出',
          suffixIcon: PopupMenuButton<int>(
            enabled: _autoCompactEnabled,
            tooltip: '选择常用压缩阈值',
            icon: const Icon(Icons.arrow_drop_down_rounded),
            onSelected: (value) {
              _autoCompactController.text = '$value';
              _saveAutoCompactTokens(value);
            },
            itemBuilder: (_) => [
              for (final tokens in _quickContextWindows)
                PopupMenuItem<int>(
                  value: tokens,
                  child: Text(
                    _formatContextWindowLabel(tokens),
                    style: AppType.label,
                  ),
                ),
            ],
          ),
        ),
        onChanged: (text) {
          final value = int.tryParse(text.trim());
          if (value == null || value < 8000) return;
          _saveAutoCompactTokens(value);
        },
      ),
      const SizedBox(height: AppSpace.x3),
      SizedBox(
        width: double.infinity,
        height: 48,
        child: OutlinedButton.icon(
          onPressed: _isTestingApi ? null : _testConnection,
          icon: _isTestingApi
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.bolt_rounded, size: 18),
          label: Text(
            _isTestingApi ? '正在测试连接中...' : '测试 API 连通性',
            style: AppType.label,
          ),
          style: _matchedFieldButtonStyle(
            isDark,
            minimumSize: const Size.fromHeight(48),
          ),
        ),
      ),
    ];
  }
}
