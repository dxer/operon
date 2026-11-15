import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/app_theme.dart';
import '../../config/app_tokens.dart';
import '../../models/download_item.dart';
import '../../services/download_service.dart';
import '../../services/haptic_service.dart';

class DownloadsSheet extends StatefulWidget {
  const DownloadsSheet({super.key, DownloadService? service})
      : _service = service;

  final DownloadService? _service;

  @override
  State<DownloadsSheet> createState() => _DownloadsSheetState();
}

class _DownloadsSheetState extends State<DownloadsSheet> {
  late final DownloadService _service = widget._service ?? DownloadService.instance;

  @override
  void initState() {
    super.initState();
    _service.init();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppTheme.darkCard : AppTheme.lightCard;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.78,
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpace.page,
        AppSpace.x3,
        AppSpace.page,
        AppSpace.x3,
      ),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x44000000),
            blurRadius: 18,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: _service,
          builder: (context, _) {
            final items = _service.items;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppInk.tertiary(isDark).withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      '下载管理',
                      style: AppType.body.copyWith(
                        color: AppInk.primary(isDark),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_service.activeCount > 0) ...[
                      const SizedBox(width: AppSpace.x2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpace.x2,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppInk.accentTint(isDark),
                          borderRadius: BorderRadius.circular(AppRadius.chip),
                        ),
                        child: Text(
                          '${_service.activeCount} 进行中',
                          style: AppType.micro.copyWith(
                            color: AppTheme.primaryOf(isDark),
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (items.any((e) => e.status != DownloadStatus.downloading))
                      TextButton(
                        onPressed: () {
                          HapticService.light();
                          _service.clearCompleted();
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: AppInk.secondary(isDark),
                          textStyle: AppType.label,
                        ),
                        child: const Text('清空记录'),
                      ),
                  ],
                ),
                const Divider(height: AppSpace.x4),
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpace.x8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.download_done_rounded,
                          size: 34,
                          color: AppInk.tertiary(isDark),
                        ),
                        const SizedBox(height: AppSpace.x2),
                        Text(
                          '暂无下载记录',
                          style: AppType.body.copyWith(
                            color: AppInk.secondary(isDark),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (_, __) => Divider(
                        height: AppStroke.hairline,
                        color: AppInk.hairline(isDark),
                      ),
                      itemBuilder: (context, index) => _DownloadRow(
                        item: items[index],
                        isDark: isDark,
                        onOpen: () async {
                          final ok = await _service.openFile(items[index]);
                          if (!ok && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('找不到本地文件，可尝试重新下载')),
                            );
                          }
                        },
                        onCancel: () => _service.cancel(items[index].id),
                        onRetry: () => _service.retry(items[index].id),
                        onCopyUrl: () {
                          Clipboard.setData(
                            ClipboardData(text: items[index].url),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已复制下载链接')),
                          );
                        },
                        onDelete: () =>
                            _service.remove(items[index].id, deleteFile: true),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DownloadRow extends StatelessWidget {
  const _DownloadRow({
    required this.item,
    required this.isDark,
    required this.onOpen,
    required this.onCancel,
    required this.onRetry,
    required this.onCopyUrl,
    required this.onDelete,
  });

  final DownloadItem item;
  final bool isDark;
  final VoidCallback onOpen;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onCopyUrl;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.primaryOf(isDark);
    final danger = AppTheme.dangerOf(isDark);
    final secondary = AppInk.secondary(isDark);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.x2),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppInk.sunken(isDark),
              borderRadius: BorderRadius.circular(AppRadius.icon),
            ),
            child: Icon(
              switch (item.status) {
                DownloadStatus.downloading => Icons.downloading_rounded,
                DownloadStatus.completed => Icons.insert_drive_file_outlined,
                DownloadStatus.failed => Icons.error_outline_rounded,
                DownloadStatus.cancelled => Icons.cancel_outlined,
              },
              size: 18,
              color: item.status == DownloadStatus.failed
                  ? danger
                  : (item.status == DownloadStatus.completed
                      ? primary
                      : secondary),
            ),
          ),
          const SizedBox(width: AppSpace.x3),
          Expanded(
            child: InkWell(
              onTap: item.status == DownloadStatus.completed ? onOpen : null,
              borderRadius: BorderRadius.circular(AppRadius.chip),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.label.copyWith(
                      color: AppInk.primary(isDark),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.statusLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.caption.copyWith(
                      color: item.status == DownloadStatus.failed
                          ? danger
                          : secondary,
                    ),
                  ),
                  if (item.status == DownloadStatus.downloading) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: item.progress,
                        minHeight: 3,
                        backgroundColor: AppInk.hairline(isDark),
                        valueColor: AlwaysStoppedAnimation<Color>(primary),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpace.x1),
          if (item.status == DownloadStatus.downloading)
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              tooltip: '取消下载',
              onPressed: onCancel,
            )
          else ...[
            if (item.status == DownloadStatus.completed)
              IconButton(
                icon: Icon(Icons.open_in_new_rounded, size: 18, color: primary),
                tooltip: '打开文件',
                onPressed: onOpen,
              )
            else
              IconButton(
                icon: Icon(Icons.refresh_rounded, size: 18, color: primary),
                tooltip: '重试',
                onPressed: onRetry,
              ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded, size: 18, color: secondary),
              onSelected: (value) {
                if (value == 'copy') onCopyUrl();
                if (value == 'delete') onDelete();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'copy', child: Text('复制链接')),
                PopupMenuItem(value: 'delete', child: Text('删除记录与文件')),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
