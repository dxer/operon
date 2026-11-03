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
  late StorageService _storage;
  bool _isLoading = true;

  int _maxSteps = 15;
  bool _safeMode = true;
  List<String> _allowedSites = [];

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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('单次任务最大执行步数',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    Text('$_maxSteps 步',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary)),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  '防止模型在复杂页面寻路陷入死循环，步数耗尽将自动挂起',
                  style: TextStyle(fontSize: 12, color: AppTheme.neutral),
                ),
                const SizedBox(height: 8),
                Slider(
                  value: _maxSteps.toDouble(),
                  min: 5,
                  max: 30,
                  divisions: 25,
                  label: '$_maxSteps',
                  activeColor: AppTheme.primary,
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
              subtitle: const Text(
                  '开启：支付、发布、删除等高危操作会暂停并等待你确认。关闭：AI 将自动执行全部操作，不再询问。',
                  style: TextStyle(fontSize: 12, color: AppTheme.neutral)),
              value: _safeMode,
              activeThumbColor: AppTheme.primary,
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
                          foregroundColor: AppTheme.danger,
                          minimumSize: const Size(0, 28),
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                        ),
                        child: const Text('清空', style: TextStyle(fontSize: 12)),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  '这些站点上的敏感操作会直接执行，不再弹出授权确认。仅在你完全信任的网站上添加。',
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.neutral, height: 1.4),
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
                          const Icon(Icons.verified_user_outlined,
                              size: 15, color: AppTheme.accent),
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
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '触屏即接管机制 (Touch-to-Interrupt)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 6),
                Text(
                  'AI 正在执行网页滚动、点击或键入时，只要用户手指触碰网页任意区域，AI 将在毫秒级内自动挂起暂停，底部的 AI 状态条会变更为“已暂停 (接管中)”，确保人机共存无冲突。',
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.neutral, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
