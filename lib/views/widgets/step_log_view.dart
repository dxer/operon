import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/agent_state.dart';

class StepLogView extends StatelessWidget {
  final List<AgentLogItem> logs;

  const StepLogView({super.key, required this.logs});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    final subtle = theme.colorScheme.onSurface.withValues(alpha: 0.38);

    if (logs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            '尚未开始执行，输入任务指令后点击开始',
            style: TextStyle(color: subtle, fontSize: 13),
          ),
        ),
      );
    }

    return ListView.builder(
      reverse: true, // Show newest at the bottom
      shrinkWrap: true,
      physics: const ClampingScrollPhysics(),
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final log = logs[logs.length - 1 - index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 2),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: log.isError
                      ? Colors.redAccent.withValues(alpha: 0.2)
                      : AppTheme.primary.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  log.step > 0 ? '${log.step}' : '•',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: log.isError ? Colors.redAccent : AppTheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      log.title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: log.isError
                            ? Colors.redAccent
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                    if (log.detail != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        log.detail!,
                        style: TextStyle(
                          fontSize: 11,
                          color: muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
