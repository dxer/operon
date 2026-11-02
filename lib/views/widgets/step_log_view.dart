import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/agent_state.dart';

class StepLogView extends StatelessWidget {
  final List<AgentLogItem> logs;

  const StepLogView({Key? key, required this.logs}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text(
            '尚未开始执行，输入任务指令后点击开始',
            style: TextStyle(color: Colors.white54, fontSize: 13),
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
                      ? Colors.redAccent.withOpacity(0.2)
                      : AppTheme.primary.withOpacity(0.2),
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
                        color: log.isError ? Colors.redAccent : Colors.white,
                      ),
                    ),
                    if (log.detail != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        log.detail!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white70,
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
