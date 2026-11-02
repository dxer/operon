import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/quick_command.dart';
import '../../services/quick_command_service.dart';

class QuickCommandsPage extends StatefulWidget {
  const QuickCommandsPage({super.key});

  @override
  State<QuickCommandsPage> createState() => _QuickCommandsPageState();
}

class _QuickCommandsPageState extends State<QuickCommandsPage> {
  QuickCommandService? _service;
  List<QuickCommand> _commands = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _service = await QuickCommandService.getInstance();
    if (!mounted) return;
    setState(() {
      _commands = _service!.getCommands();
      _isLoading = false;
    });
  }

  Future<void> _edit(QuickCommand? command) async {
    final result = await Navigator.of(context).push<QuickCommand>(
      MaterialPageRoute(
        builder: (_) => QuickCommandEditPage(command: command),
      ),
    );
    if (result == null || !mounted) return;
    await _service!.saveCommand(result);
    await _load();
  }

  Future<void> _delete(QuickCommand command) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除快捷指令？'),
        content: Text('「${command.title}」将从列表中移除，已有历史记录不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _service!.deleteCommand(command.id);
    await _load();
  }

  Future<void> _restoreDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复默认快捷指令？'),
        content: const Text('当前自定义指令会被覆盖，恢复为内置的通用模板。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('恢复', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _service!.restoreDefaults();
    await _load();
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final list = [..._commands];
    final item = list.removeAt(oldIndex);
    final target =
        newIndex < 0 ? 0 : (newIndex > list.length ? list.length : newIndex);
    list.insert(target, item);
    setState(() => _commands = list);
    await _service!.saveCommands(list);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('快捷指令'),
        actions: [
          IconButton(
            tooltip: '恢复默认',
            icon: const Icon(Icons.restore_rounded),
            onPressed: _isLoading ? null : _restoreDefaults,
          ),
          IconButton(
            tooltip: '新增快捷指令',
            icon: const Icon(Icons.add_rounded),
            onPressed: _isLoading ? null : () => _edit(null),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _commands.isEmpty
              ? _buildEmpty(context)
              : ReorderableListView.builder(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    12,
                    16,
                    16 + MediaQuery.of(context).viewPadding.bottom,
                  ),
                  itemCount: _commands.length,
                  onReorderItem: _reorder,
                  itemBuilder: (context, index) {
                    final command = _commands[index];
                    return _CommandCard(
                      key: ValueKey(command.id),
                      command: command,
                      isDark: isDark,
                      onEdit: () => _edit(command),
                      onDelete: () => _delete(command),
                    );
                  },
                ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt_rounded, size: 56, color: muted),
          const SizedBox(height: 12),
          Text('还没有快捷指令', style: TextStyle(color: muted)),
          const SizedBox(height: 6),
          Text(
            '点击右上角 + 新建，或恢复默认模板',
            style: TextStyle(fontSize: 12, color: muted.withValues(alpha: 0.8)),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _restoreDefaults,
            icon: const Icon(Icons.restore_rounded, size: 16),
            label: const Text('恢复默认模板'),
          ),
        ],
      ),
    );
  }
}

class _CommandCard extends StatelessWidget {
  final QuickCommand command;
  final bool isDark;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CommandCard({
    super.key,
    required this.command,
    required this.isDark,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;
    final border = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final muted = onSurface.withValues(alpha: 0.55);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: 0.8),
      ),
      child: ListTile(
        onTap: onEdit,
        contentPadding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        leading: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.bolt_rounded, size: 18, color: Colors.amber),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                command.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: onSurface,
                ),
              ),
            ),
            if (command.builtin) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Text(
                  '内置',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.accent,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (command.description.isNotEmpty)
                Text(
                  command.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: muted, height: 1.35),
                ),
              const SizedBox(height: 4),
              Text(
                '${command.policy.mode.label} · '
                '${command.inputs.length} 个参数 · '
                '最多 ${command.policy.maxItems} '
                '${command.policy.mode == QuickCommandMode.paginate ? '页' : '项'}',
                style: TextStyle(fontSize: 10.5, color: muted),
              ),
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '编辑',
              icon: const Icon(Icons.edit_outlined, size: 18),
              visualDensity: VisualDensity.compact,
              onPressed: onEdit,
            ),
            IconButton(
              tooltip: '删除',
              icon: const Icon(Icons.delete_outline, size: 18),
              visualDensity: VisualDensity.compact,
              color: Colors.redAccent,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class QuickCommandEditPage extends StatefulWidget {
  final QuickCommand? command;

  const QuickCommandEditPage({super.key, this.command});

  @override
  State<QuickCommandEditPage> createState() => _QuickCommandEditPageState();
}

class _QuickCommandEditPageState extends State<QuickCommandEditPage> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _promptController;
  late final TextEditingController _maxItemsController;
  late final TextEditingController _pacingController;
  late final TextEditingController _maxStepsController;
  late List<QuickCommandInput> _inputs;
  late QuickCommandMode _mode;
  late bool _uniqueTarget;
  late bool _uniqueContent;
  late bool _confirmBeforeSideEffect;
  late bool _showPayloadInConfirmation;
  late List<String> _stopOn;

  bool get _isNew => widget.command == null;

  @override
  void initState() {
    super.initState();
    final command = widget.command;
    _titleController = TextEditingController(text: command?.title ?? '');
    _descriptionController =
        TextEditingController(text: command?.description ?? '');
    _promptController =
        TextEditingController(text: command?.promptTemplate ?? '');
    _inputs = List<QuickCommandInput>.from(command?.inputs ?? const []);
    final policy = command?.policy ?? const QuickCommandPolicy();
    _mode = policy.mode;
    _uniqueTarget = policy.uniqueTarget;
    _uniqueContent = policy.uniqueContent;
    _confirmBeforeSideEffect = policy.confirmBeforeSideEffect;
    _showPayloadInConfirmation = policy.showPayloadInConfirmation;
    _stopOn = List<String>.from(policy.stopOn);
    _maxItemsController =
        TextEditingController(text: policy.maxItems.toString());
    _pacingController =
        TextEditingController(text: (policy.pacingMs ~/ 1000).toString());
    _maxStepsController = TextEditingController(
      text: policy.maxSteps == null ? '' : policy.maxSteps.toString(),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _promptController.dispose();
    _maxItemsController.dispose();
    _pacingController.dispose();
    _maxStepsController.dispose();
    super.dispose();
  }

  Future<void> _editInput({QuickCommandInput? input, int? index}) async {
    final result = await showDialog<QuickCommandInput>(
      context: context,
      builder: (_) => QuickCommandInputDialog(input: input),
    );
    if (result == null || !mounted) return;
    final duplicate = _inputs.any(
      (item) =>
          item.key == result.key && (index == null || item != _inputs[index]),
    );
    if (duplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('参数 key「${result.key}」已存在')),
      );
      return;
    }
    setState(() {
      if (index == null) {
        _inputs.add(result);
      } else {
        _inputs[index] = result;
      }
    });
  }

  void _removeInput(int index) {
    if (index < 0 || index >= _inputs.length) return;
    final removed = _inputs[index];
    setState(() => _inputs.removeAt(index));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已删除参数「${removed.label}」'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            if (!mounted) return;
            final target = index > _inputs.length ? _inputs.length : index;
            setState(() => _inputs.insert(target, removed));
          },
        ),
      ),
    );
  }

  void _save() {
    final title = _titleController.text.trim();
    final prompt = _promptController.text.trim();
    if (title.isEmpty) {
      _showError('请填写名称');
      return;
    }
    if (prompt.isEmpty) {
      _showError('请填写提示词');
      return;
    }
    for (final input in _inputs) {
      if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(input.key)) {
        _showError('参数 key「${input.key}」只能包含字母、数字和下划线');
        return;
      }
      if (input.label.trim().isEmpty) {
        _showError('参数「${input.key}」缺少显示名称');
        return;
      }
    }

    final maxItems = int.tryParse(_maxItemsController.text.trim()) ?? 1;
    final pacingSeconds = int.tryParse(_pacingController.text.trim()) ?? 0;
    final maxSteps = int.tryParse(_maxStepsController.text.trim());

    final command = QuickCommand(
      id: widget.command?.id ??
          'quick_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      description: _descriptionController.text.trim(),
      promptTemplate: prompt,
      inputs: List.unmodifiable(_inputs),
      policy: QuickCommandPolicy(
        mode: _mode,
        maxItems: maxItems < 1 ? 1 : maxItems,
        uniqueTarget: _uniqueTarget,
        uniqueContent: _uniqueContent,
        pacingMs: pacingSeconds < 0 ? 0 : pacingSeconds * 1000,
        confirmBeforeSideEffect: _confirmBeforeSideEffect,
        showPayloadInConfirmation: _showPayloadInConfirmation,
        maxSteps: maxSteps == null || maxSteps < 1 ? null : maxSteps,
        stopOn: _stopOn,
      ),
      builtin: widget.command?.builtin ?? false,
      sortOrder: widget.command?.sortOrder ?? 0,
    );
    Navigator.of(context).pop(command);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final muted = onSurface.withValues(alpha: 0.55);
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;
    final border = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? '新建快捷指令' : '编辑快捷指令'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text(
              '保存',
              style: TextStyle(
                color: AppTheme.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          24 + MediaQuery.of(context).viewPadding.bottom,
        ),
        children: [
          _sectionTitle('基本信息', onSurface),
          const SizedBox(height: 8),
          TextField(
            controller: _titleController,
            decoration: _inputDecoration('名称', '例如：批量智能回复'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _descriptionController,
            maxLines: 2,
            decoration: _inputDecoration('说明', '这个指令做什么、适合什么场景'),
          ),
          const SizedBox(height: 16),
          _sectionTitle('提示词', onSurface),
          const SizedBox(height: 4),
          Text(
            '使用 {{参数key}} 插入参数。提示词只描述目标和约束，不要写死某个网站的选择器。',
            style: TextStyle(fontSize: 11.5, color: muted, height: 1.4),
          ),
          const SizedBox(height: 8),
          if (_inputs.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _inputs
                  .map((input) => ActionChip(
                        label: Text(
                          '{{${input.key}}}',
                          style: const TextStyle(fontSize: 10.5),
                        ),
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          final text = _promptController.text;
                          final selection = _promptController.selection;
                          final offset =
                              selection.isValid ? selection.start : text.length;
                          final insert = '{{${input.key}}}';
                          final next =
                              text.replaceRange(offset, offset, insert);
                          _promptController.value = TextEditingValue(
                            text: next,
                            selection: TextSelection.collapsed(
                              offset: offset + insert.length,
                            ),
                          );
                        },
                      ))
                  .toList(),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _promptController,
            minLines: 8,
            maxLines: 16,
            style: const TextStyle(fontSize: 12.5, height: 1.45),
            decoration: _inputDecoration('提示词模板', '描述目标、约束和输出要求'),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _sectionTitle('参数', onSurface),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _editInput(),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('添加参数', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  minimumSize: const Size(0, 30),
                ),
              ),
            ],
          ),
          if (_inputs.isEmpty)
            Text(
              '没有参数。提示词里的 {{变量}} 会保持为空。',
              style: TextStyle(fontSize: 11.5, color: muted),
            )
          else
            ...List.generate(_inputs.length, (index) {
              final input = _inputs[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: border, width: 0.8),
                ),
                child: ListTile(
                  dense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  title: Text(
                    input.label,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  subtitle: Text(
                    '{{${input.key}}} · ${input.type.label}'
                    '${input.required ? ' · 必填' : ''} · 默认：'
                    '${input.defaultValue.isEmpty ? '（空）' : input.defaultValue}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: muted),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 17),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _editInput(input: input, index: index),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 17),
                        color: Colors.redAccent,
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _removeInput(index),
                      ),
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 16),
          _sectionTitle('执行策略', onSurface),
          const SizedBox(height: 8),
          InputDecorator(
            decoration: _inputDecoration('执行模式', ''),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<QuickCommandMode>(
                value: _mode,
                isExpanded: true,
                isDense: true,
                items: QuickCommandMode.values
                    .map((mode) => DropdownMenuItem(
                          value: mode,
                          child: Text(mode.label,
                              style: const TextStyle(fontSize: 13)),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _mode = value);
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _maxItemsController,
                  keyboardType: TextInputType.number,
                  decoration: _inputDecoration('最多处理数', '批量任务上限'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _pacingController,
                  keyboardType: TextInputType.number,
                  decoration: _inputDecoration('间隔秒数', '每条之间'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _maxStepsController,
            keyboardType: TextInputType.number,
            decoration: _inputDecoration('最大步数', '留空则使用全局设置'),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('同一目标只处理一次', style: TextStyle(fontSize: 13)),
            subtitle: Text(
              '批量任务中阻止重复处理同一条目',
              style: TextStyle(fontSize: 11, color: muted),
            ),
            value: _uniqueTarget,
            activeThumbColor: AppTheme.primary,
            onChanged: (value) => setState(() => _uniqueTarget = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('阻止重复内容', style: TextStyle(fontSize: 13)),
            subtitle: Text(
              '相同或高度相似的文本不会重复发送',
              style: TextStyle(fontSize: 11, color: muted),
            ),
            value: _uniqueContent,
            activeThumbColor: AppTheme.primary,
            onChanged: (value) => setState(() => _uniqueContent = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('敏感操作仍要求确认', style: TextStyle(fontSize: 13)),
            subtitle: Text(
              '即使关闭全局安全模式，本指令也会先询问',
              style: TextStyle(fontSize: 11, color: muted),
            ),
            value: _confirmBeforeSideEffect,
            activeThumbColor: AppTheme.primary,
            onChanged: (value) =>
                setState(() => _confirmBeforeSideEffect = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('确认时显示发送内容', style: TextStyle(fontSize: 13)),
            subtitle: Text(
              '授权弹窗展示准备发送的文本或 URL',
              style: TextStyle(fontSize: 11, color: muted),
            ),
            value: _showPayloadInConfirmation,
            activeThumbColor: AppTheme.primary,
            onChanged: (value) =>
                setState(() => _showPayloadInConfirmation = value),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text, Color onSurface) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: onSurface,
      ),
    );
  }

  InputDecoration _inputDecoration(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint.isEmpty ? null : hint,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }
}

class QuickCommandInputDialog extends StatefulWidget {
  final QuickCommandInput? input;

  const QuickCommandInputDialog({super.key, this.input});

  @override
  State<QuickCommandInputDialog> createState() =>
      _QuickCommandInputDialogState();
}

class _QuickCommandInputDialogState extends State<QuickCommandInputDialog> {
  late final TextEditingController _keyController;
  late final TextEditingController _labelController;
  late final TextEditingController _defaultController;
  late final TextEditingController _optionsController;
  late QuickCommandInputType _type;
  late bool _required;

  @override
  void initState() {
    super.initState();
    final input = widget.input;
    _keyController = TextEditingController(text: input?.key ?? '');
    _labelController = TextEditingController(text: input?.label ?? '');
    _defaultController = TextEditingController(text: input?.defaultValue ?? '');
    _optionsController =
        TextEditingController(text: input?.options.join(', ') ?? '');
    _type = input?.type ?? QuickCommandInputType.text;
    _required = input?.required ?? false;
  }

  @override
  void dispose() {
    _keyController.dispose();
    _labelController.dispose();
    _defaultController.dispose();
    _optionsController.dispose();
    super.dispose();
  }

  void _submit() {
    final key = _keyController.text.trim();
    final label = _labelController.text.trim();
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(key)) {
      _error('key 只能包含字母、数字和下划线');
      return;
    }
    if (label.isEmpty) {
      _error('请填写显示名称');
      return;
    }
    final options = _optionsController.text
        .split(RegExp(r'[,，]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (_type == QuickCommandInputType.select && options.isEmpty) {
      _error('单选类型至少需要一个选项');
      return;
    }
    Navigator.of(context).pop(
      QuickCommandInput(
        key: key,
        label: label,
        type: _type,
        defaultValue: _defaultController.text.trim(),
        options: options,
        required: _required,
      ),
    );
  }

  void _error(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.input == null ? '添加参数' : '编辑参数'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _keyController,
              decoration: const InputDecoration(
                labelText: '参数 key',
                hintText: '例如 count',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _labelController,
              decoration: const InputDecoration(
                labelText: '显示名称',
                hintText: '例如 处理条数',
              ),
            ),
            const SizedBox(height: 10),
            InputDecorator(
              decoration: const InputDecoration(labelText: '类型'),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<QuickCommandInputType>(
                  value: _type,
                  isExpanded: true,
                  isDense: true,
                  items: QuickCommandInputType.values
                      .map((type) => DropdownMenuItem(
                            value: type,
                            child: Text(type.label,
                                style: const TextStyle(fontSize: 13)),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _type = value);
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _defaultController,
              minLines: _type == QuickCommandInputType.multiline ? 2 : 1,
              maxLines: _type == QuickCommandInputType.multiline ? 4 : 1,
              decoration: const InputDecoration(labelText: '默认值'),
            ),
            if (_type == QuickCommandInputType.select) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _optionsController,
                decoration: const InputDecoration(
                  labelText: '选项',
                  hintText: '用逗号分隔，例如 友好, 专业, 幽默',
                ),
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('必填', style: TextStyle(fontSize: 13)),
              subtitle: const Text(
                '空值时阻止填入输入框',
                style: TextStyle(fontSize: 11),
              ),
              value: _required,
              activeThumbColor: AppTheme.accent,
              onChanged: (value) => setState(() => _required = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
          child: const Text('确定', style: TextStyle(color: Colors.black)),
        ),
      ],
    );
  }
}
