import '../models/agent_task_record.dart';

/// One task record as a Markdown report.
///
/// The history page keeps a record for auditing; this is the same record in a
/// form the user can paste into a note, a chat or a bug report. Plain text on
/// purpose: it has to survive the clipboard and any destination.
String taskRecordToMarkdown(AgentTaskRecord record) {
  final buffer = StringBuffer()
    ..writeln('# ${record.goal.isEmpty ? '未命名任务' : record.goal}')
    ..writeln()
    ..writeln('- 状态：${taskStatusLabel(record.status)}')
    ..writeln('- 开始：${_stamp(record.startedAt)}')
    ..writeln('- 耗时：${durationLabel(record.duration)}')
    ..writeln('- 步数：${record.steps} / ${record.maxSteps}')
    ..writeln('- 人工授权：${record.safeMode ? '开启' : '关闭'}');

  final url = record.targetUrl;
  if (url != null && url.isNotEmpty && !url.startsWith('operon://')) {
    buffer.writeln('- 页面：$url');
  }

  if (record.hasSensitiveActions) {
    buffer
      ..writeln()
      ..writeln('## 敏感操作')
      ..writeln();
    for (final action in record.sensitiveActions) {
      buffer.writeln('- $action');
    }
  }

  final error = record.errorMessage;
  if (error != null && error.trim().isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('## 错误')
      ..writeln()
      ..writeln(error.trim());
  }

  if (record.logs.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('## 执行记录')
      ..writeln()
      ..writeln('```');
    for (final line in record.logs) {
      buffer.writeln(line);
    }
    buffer.writeln('```');
  }

  return buffer.toString().trimRight();
}

String taskStatusLabel(String status) {
  switch (status) {
    case 'completed':
      return '已完成';
    case 'maxStepsReached':
      return '达到步数上限';
    case 'error':
      return '执行异常';
    case 'stopped':
      return '已手动停止';
    default:
      return status;
  }
}

String durationLabel(Duration duration) {
  if (duration.inSeconds < 60) return '${duration.inSeconds} 秒';
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds % 60;
  return '$minutes 分 $seconds 秒';
}

String _stamp(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)} '
      '${two(time.hour)}:${two(time.minute)}';
}
