import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../config/app_constants.dart';
import '../../config/app_theme.dart';
import '../../config/app_tokens.dart';
import '../../services/storage_service.dart';
import '../widgets/operon_list_row.dart';

class GeneralSettingsPage extends StatefulWidget {
  const GeneralSettingsPage({super.key});

  @override
  State<GeneralSettingsPage> createState() => _GeneralSettingsPageState();
}

class _GeneralSettingsPageState extends State<GeneralSettingsPage> {
  late StorageService _storage;
  bool _isLoading = true;
  String _selectedSearchEngine = AppConstants.defaultSearchEngine;
  bool _restoreTabs = true;
  final TextEditingController _homepageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _homepageController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    _storage = await StorageService.getInstance();
    _selectedSearchEngine = _storage.getSearchEngine();
    _restoreTabs = _storage.getRestoreTabsEnabled();
    _homepageController.text = _storage.getHomepage();
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  Future<void> _showClearBrowsingDataDialog() async {
    bool clearCookies = true;
    bool clearCache = true;
    bool clearStorage = true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            title: const Text(
              '清除浏览数据与缓存',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CheckboxListTile(
                  dense: true,
                  title: const Text(
                    'Cookie 与网站登录状态',
                    style: TextStyle(fontSize: 13),
                  ),
                  value: clearCookies,
                  activeColor: AppTheme.primaryOf(isDark),
                  onChanged: (val) =>
                      setDialogState(() => clearCookies = val ?? false),
                ),
                CheckboxListTile(
                  dense: true,
                  title: const Text(
                    '网页缓存文件 (Cache)',
                    style: TextStyle(fontSize: 13),
                  ),
                  value: clearCache,
                  activeColor: AppTheme.primaryOf(isDark),
                  onChanged: (val) =>
                      setDialogState(() => clearCache = val ?? false),
                ),
                CheckboxListTile(
                  dense: true,
                  title: const Text(
                    '本地存储 (LocalStorage / IndexedDB)',
                    style: TextStyle(fontSize: 13),
                  ),
                  value: clearStorage,
                  activeColor: AppTheme.primaryOf(isDark),
                  onChanged: (val) =>
                      setDialogState(() => clearStorage = val ?? false),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: (clearCookies || clearCache || clearStorage)
                    ? () => Navigator.of(ctx).pop(true)
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.dangerOf(isDark),
                  foregroundColor: Colors.white,
                ),
                child: const Text('确认清除'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed == true) {
      if (clearCookies) {
        await CookieManager.instance().deleteAllCookies();
      }
      if (clearStorage) {
        await WebStorageManager.instance().deleteAllData();
      }
      if (clearCache) {
        await InAppWebViewController.clearAllCache();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已清除选中的浏览数据与本地缓存')),
        );
      }
    }
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
        title: const Text('通用与搜索'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, 16 + MediaQuery.of(context).viewPadding.bottom),
        children: [
          Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(AppRadius.icon),
              border: Border.all(
                color: AppInk.hairline(isDark),
                width: AppStroke.hairline,
              ),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '搜索与主页',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                OperonOptionRow<String>(
                  title: '默认搜索引擎',
                  padding: EdgeInsets.zero,
                  value: AppConstants.searchEngines
                          .containsKey(_selectedSearchEngine)
                      ? _selectedSearchEngine
                      : AppConstants.defaultSearchEngine,
                  options: [
                    for (final engine in AppConstants.searchEngines.keys)
                      OperonOptionItem<String>(
                        value: engine,
                        label: engine,
                        subtitle: AppConstants.searchEngines[engine],
                      ),
                  ],
                  onChanged: (val) async {
                    setState(() => _selectedSearchEngine = val);
                    await _storage.saveSearchEngine(val);
                  },
                ),
                Divider(
                  height: 12,
                  thickness: AppStroke.hairline,
                  color: AppInk.hairline(isDark),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _homepageController,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    labelText: '主页网址',
                    hintText: AppConstants.defaultHomepage,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.restore_rounded, size: 18),
                      tooltip: '恢复默认主页',
                      onPressed: () {
                        _homepageController.text = AppConstants.defaultHomepage;
                        _storage.saveHomepage(AppConstants.defaultHomepage);
                        setState(() {});
                      },
                    ),
                  ),
                  onChanged: (val) => _storage.saveHomepage(val.trim()),
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    '启动时恢复上次打开的标签页',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    '仅保留普通标签页，不含无痕标签',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppInk.tertiary(isDark),
                    ),
                  ),
                  value: _restoreTabs,
                  activeThumbColor: AppTheme.primaryOf(isDark),
                  onChanged: (val) async {
                    setState(() => _restoreTabs = val);
                    await _storage.saveRestoreTabsEnabled(val);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(AppRadius.icon),
              border: Border.all(
                color: AppInk.hairline(isDark),
                width: AppStroke.hairline,
              ),
            ),
            child: ListTile(
              dense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              leading: Icon(Icons.delete_sweep_rounded,
                  size: 20, color: AppTheme.dangerOf(isDark)),
              title: const Text('清除浏览数据与缓存',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              trailing: Icon(Icons.chevron_right_rounded,
                  size: 18, color: AppInk.tertiary(isDark)),
              onTap: _showClearBrowsingDataDialog,
            ),
          ),
        ],
      ),
    );
  }
}
