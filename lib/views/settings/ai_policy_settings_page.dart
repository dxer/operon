import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../services/storage_service.dart';

class AiPolicySettingsPage extends StatefulWidget {
  const AiPolicySettingsPage({super.key});

  @override
  State<AiPolicySettingsPage> createState() => _AiPolicySettingsPageState();
}

class _AiPolicySettingsPageState extends State<AiPolicySettingsPage> {
  late StorageService _storage;
  bool _isLoading = true;

  int _maxSteps = 15;
  bool _safeMode = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _storage = await StorageService.getInstance();
    _maxSteps = _storage.getMaxSteps();
    _safeMode = _storage.getSafeMode();
    if (!mounted) return;
    setState(() => _isLoading = false);
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
                  style: TextStyle(fontSize: 12, color: Colors.grey),
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
              title: const Text('敏感操作人工确认 (Safe Mode)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: const Text('遇到支付、删除、敏感提交等高危操作时主动挂起并弹出弹窗征询授权',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              value: _safeMode,
              activeThumbColor: AppTheme.primary,
              onChanged: (val) async {
                setState(() => _safeMode = val);
                await _storage.saveSafeMode(val);
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
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '触屏即接管机制 (Touch-to-Interrupt)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 6),
                Text(
                  'AI 正在执行网页滚动、点击或键入时，只要用户手指触碰网页任意区域，AI 将在毫秒级内自动挂起暂停，底部灵动胶囊将变更为“已暂停 (接管中)”，确保人机共存无冲突。',
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
