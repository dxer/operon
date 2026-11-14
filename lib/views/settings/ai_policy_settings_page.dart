import 'dart:async';

import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../services/storage_service.dart';

class AiPolicySettingsPage extends StatefulWidget {
  /// Invoked immediately so an in-flight agent stops asking for confirmation.
  final ValueChanged<bool>? onSafeModeChanged;

  const AiPolicySettingsPage({super.key, this.onSafeModeChanged});

  @override
  State<AiPolicySettingsPage> createState() => _AiPolicySettingsPageState();
}

class _AiPolicySettingsPageState extends State<AiPolicySettingsPage> {
  /// Enough for a paragraph of preferences; a long memory is context the run
  /// pays for on every turn.
  static const int _memoryLimit = 600;

  late StorageService _storage;
  bool _isLoading = true;

  int _maxSteps = 15;
  bool _safeMode = true;
  List<String> _allowedSites = [];
  final TextEditingController _memoryController = TextEditingController();
  Timer? _memoryDebounce;
  List<String> _blockedSites = [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _storage = await StorageService.getInstance();
    _maxSteps = _storage.getMaxSteps();
    _safeMode = _storage.getSafeMode();
    _allowedSites = _storage.getAgentAllowedSites();
    _blockedSites = _storage.getAgentBlockedSites();
    _memoryController.text = _storage.getAgentMemory();
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  Future<void> _removeSite(String host) async {
    await _storage.removeAgentAllowedSite(host);
    if (!mounted) return;
    setState(() => _allowedSites = _storage.getAgentAllowedSites());
  }

  Future<void> _clearSites() async {
    await _storage.clearAgentAllowedSites();
    if (!mounted) return;
    setState(() => _allowedSites = const []);
  }

  @override
  void dispose() {
    // A note typed in the last moment is still owed to the store.
    if (_memoryDebounce?.isActive ?? false) {
      _memoryDebounce!.cancel();
      unawaited(_storage.saveAgentMemory(_memoryController.text));
    }
    _memoryController.dispose();
    _memoryDebounce?.cancel();
    super.dispose();
  }

  void _scheduleMemorySave() {
    _memoryDebounce?.cancel();
    _memoryDebounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(_storage.saveAgentMemory(_memoryController.text));
    });
  }

  Future<void> _removeBlocked(String host) async {
    await _storage.removeAgentBlockedSite(host);
    if (!mounted) return;
    setState(() => _blockedSites = _storage.getAgentBlockedSites());
  }

  Future<void> _clearBlocked() async {
    await _storage.clearAgentBlockedSites();
    if (!mounted) return;
    setState(() => _blockedSites = const []);
  }

  /// Lets a host be added without waiting for the agent to meet it first.
  Future<void> _addBlocked() async {
    final controller = TextEditingController();
    final host = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('禁止一个站点'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'example.com',
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('禁止'),
          ),
        ],
      ),
    );
    if (host == null || host.isEmpty) return;
    await _storage.addAgentBlockedSite(host);
    await _storage.removeAgentAllowedSite(host);
    if (!mounted) return;
    setState(() {
      _blockedSites = _storage.getAgentBlockedSites();
      _allowedSites = _storage.getAgentAllowedSites();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 策略与自主权限'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + MediaQuery.of(context).viewPadding.bottom),
        children: [
          Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                width: 0.8,
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('长期记忆',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  '每次任务都会告诉模型的事：你是谁、你要什么样的回答、你的时区或单位。'
                  '留空则完全不发送。',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.neutralOf(isDark),
                      height: 1.4),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _memoryController,
                  minLines: 2,
                  maxLines: 5,
                  maxLength: _memoryLimit,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: '例如：我在北京，回答用简体中文，先给结论再给细节。',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => _scheduleMemorySave(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                width: 0.8,
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('单次任务最大执行步数',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    Text('$_maxSteps 步',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryOf(isDark))),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '防止模型在复杂页面寻路陷入死循环，步数耗尽将自动挂起',
                  style: TextStyle(fontSize: 12, color: AppTheme.neutralOf(isDark)),
                ),
                const SizedBox(height: 8),
                Slider(
                  value: _maxSteps.toDouble(),
                  min: 5,
                  max: 30,
                  divisions: 25,
                  label: '$_maxSteps',
                  activeColor: AppTheme.primaryOf(isDark),
                  onChanged: (val) {
                    setState(() => _maxSteps = val.round());
                  },
                  onChangeEnd: (val) async {
                    await _storage.saveMaxSteps(val.round());
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                width: 0.8,
              ),
            ),
            child: SwitchListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              title: const Text('敏感操作人工授权 (Safe Mode)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: Text(
                  '开启：支付、发布、删除等高危操作会暂停并等待你确认。关闭：AI 将自动执行全部操作，不再询问。',
                  style: TextStyle(fontSize: 12, color: AppTheme.neutralOf(isDark))),
              value: _safeMode,
              activeThumbColor: AppTheme.primaryOf(isDark),
              onChanged: (val) async {
                setState(() => _safeMode = val);
                await _storage.saveSafeMode(val);
                widget.onSafeModeChanged?.call(val);
              },
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                width: 0.8,
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '已允许自动执行的站点',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    if (_allowedSites.isNotEmpty)
                      TextButton(
                        onPressed: _clearSites,
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.dangerOf(isDark),
                          minimumSize: const Size(0, 28),
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                        ),
                        child: const Text('清空', style: TextStyle(fontSize: 12)),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '这些站点上的敏感操作会直接执行，不再弹出授权确认。仅在你完全信任的网站上添加。',
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.neutralOf(isDark), height: 1.4),
                ),
                const SizedBox(height: 8),
                if (_allowedSites.isEmpty)
                  Text(
                    '暂无信任站点',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.4),
                    ),
                  )
                else
                  ..._allowedSites.map(
                    (host) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Icon(Icons.verified_user_outlined,
                              size: 15, color: AppTheme.accentOf(isDark)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              host,
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          ),
                          IconButton(
                            tooltip: '移除 $host',
                            icon: const Icon(Icons.close_rounded, size: 16),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _removeSite(host),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                width: 0.8,
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '禁止智能体使用的站点',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    Row(
                      children: [
                        TextButton(
                          onPressed: _addBlocked,
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.primaryOf(isDark),
                            minimumSize: const Size(0, 28),
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                          ),
                          child:
                              const Text('添加', style: TextStyle(fontSize: 12)),
                        ),
                        if (_blockedSites.isNotEmpty)
                          TextButton(
                            onPressed: _clearBlocked,
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.dangerOf(isDark),
                              minimumSize: const Size(0, 28),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                            ),
                            child:
                                const Text('清空', style: TextStyle(fontSize: 12)),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '智能体在这些站点上一律不动手：不点击、不输入、不读页面。'
                  '这一条不弹授权，也不会被任何一次同意改变。',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.neutralOf(isDark),
                      height: 1.4),
                ),
                const SizedBox(height: 8),
                if (_blockedSites.isEmpty)
                  Text(
                    '暂无禁止站点',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.4),
                    ),
                  )
                else
                  ..._blockedSites.map(
                    (host) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Icon(Icons.block_rounded,
                              size: 15, color: AppTheme.dangerOf(isDark)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(host,
                                style: const TextStyle(fontSize: 12.5)),
                          ),
                          IconButton(
                            tooltip: '解除禁止 $host',
                            icon: const Icon(Icons.close_rounded, size: 16),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _removeBlocked(host),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                width: 0.8,
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '手动暂停与接管',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'AI 执行时，触摸或滚动网页不会自动暂停任务，你可以正常浏览页面。需要接管时，点击底部 AI 状态条上的暂停按钮；任务会在当前动作完成后停住，恢复后从下一步继续。',
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.neutralOf(isDark), height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
