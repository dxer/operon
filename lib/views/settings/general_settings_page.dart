import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../config/app_constants.dart';
import '../../config/app_theme.dart';
import '../../services/storage_service.dart';

class GeneralSettingsPage extends StatefulWidget {
  const GeneralSettingsPage({super.key});

  @override
  State<GeneralSettingsPage> createState() => _GeneralSettingsPageState();
}

class _GeneralSettingsPageState extends State<GeneralSettingsPage> {
  late StorageService _storage;
  bool _isLoading = true;
  String _selectedSearchEngine = AppConstants.defaultSearchEngine;
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
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('清除浏览数据与缓存',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(
                title: const Text('Cookie 与网站登录状态',
                    style: TextStyle(fontSize: 14)),
                value: clearCookies,
                activeColor: AppTheme.primary,
                onChanged: (val) =>
                    setDialogState(() => clearCookies = val ?? false),
              ),
              CheckboxListTile(
                title: const Text('网页缓存文件 (Cache)',
                    style: TextStyle(fontSize: 14)),
                subtitle: const Text('释放应用占用的图片与静态脚本存储',
                    style: TextStyle(fontSize: 12)),
                value: clearCache,
                activeColor: AppTheme.primary,
                onChanged: (val) =>
                    setDialogState(() => clearCache = val ?? false),
              ),
              CheckboxListTile(
                title: const Text('本地存储 (LocalStorage / IndexedDB)',
                    style: TextStyle(fontSize: 14)),
                value: clearStorage,
                activeColor: AppTheme.primary,
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
            ElevatedButton(
              onPressed: (clearCookies || clearCache || clearStorage)
                  ? () => Navigator.of(ctx).pop(true)
                  : null,
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
              child: const Text('确认清除', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    '默认搜索引擎',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
                RadioGroup<String>(
                  groupValue: _selectedSearchEngine,
                  onChanged: (val) async {
                    if (val != null) {
                      setState(() => _selectedSearchEngine = val);
                      await _storage.saveSearchEngine(val);
                    }
                  },
                  child: Column(
                    children: AppConstants.searchEngines.keys.map((engine) {
                      return RadioListTile<String>(
                        title:
                            Text(engine, style: const TextStyle(fontSize: 14)),
                        value: engine,
                        activeColor: AppTheme.primary,
                        dense: true,
                      );
                    }).toList(),
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
                  '主页网址',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  '新建标签页或点击底栏主页图标时打开的地址',
                  style: TextStyle(fontSize: 12, color: AppTheme.neutral),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _homepageController,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: '默认: operon://newtab (内置极简主页)',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.restore_rounded, size: 20),
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
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: const Icon(Icons.delete_sweep_rounded,
                  color: AppTheme.danger),
              title: const Text('清除浏览数据与缓存',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: const Text('清理 Cookie、LocalStorage 及离线静态资源',
                  style: TextStyle(fontSize: 12, color: AppTheme.neutral)),
              trailing: const Icon(Icons.chevron_right_rounded,
                  color: AppTheme.neutral),
              onTap: _showClearBrowsingDataDialog,
            ),
          ),
        ],
      ),
    );
  }
}
