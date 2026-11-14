import '../protocol/errors.dart';

/// One option of a native `<select>`, as the page reports it.
class SelectOption {
  const SelectOption({
    required this.index,
    required this.value,
    required this.label,
    this.disabled = false,
  });

  factory SelectOption.fromJson(Map<String, Object?> json) => SelectOption(
        index: (json['index'] as num?)?.toInt() ?? -1,
        value: json['value']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        disabled: json['disabled'] == true,
      );

  final int index;
  final String value;
  final String label;
  final bool disabled;

  @override
  String toString() => '[$index] $label';
}

/// The option the caller meant, and how it was recognised.
class SelectChoice {
  const SelectChoice({required this.option, required this.how});

  final SelectOption option;

  /// `index`, `value`, `label` or `label-contains`.
  final String how;
}

/// Picks one option, or explains why there is no unambiguous pick.
///
/// Matching lives here rather than in page script: a dropdown that answers
/// "改了但没有真的改" is the usual failure, so the choice is made where it can be
/// unit tested and the page is only told the resulting index.
///
/// Order is deliberate — an exact value beats an exact label, and a partial
/// label is the last resort because "北京" also matches "北京市朝阳区".
SelectChoice chooseOption(
  List<SelectOption> options, {
  String? label,
  String? value,
  int? index,
}) {
  final usable = options.where((option) => !option.disabled).toList(growable: false);

  if (index != null) {
    final match = options.where((option) => option.index == index).firstOrNull;
    if (match == null) {
      throw _noOption('没有 index 为 $index 的选项', options);
    }
    if (match.disabled) {
      throw _noOption('选项「${match.label}」是禁用的', options);
    }
    return SelectChoice(option: match, how: 'index');
  }

  if (value != null) {
    final match = usable.where((option) => option.value == value).firstOrNull;
    if (match != null) return SelectChoice(option: match, how: 'value');
  }

  if (label != null && label.trim().isNotEmpty) {
    final wanted = label.trim();
    final lowered = wanted.toLowerCase();
    final exact = usable
        .where((option) => option.label.trim().toLowerCase() == lowered)
        .firstOrNull;
    if (exact != null) return SelectChoice(option: exact, how: 'label');
    final partial = usable
        .where((option) => option.label.trim().toLowerCase().contains(lowered))
        .firstOrNull;
    if (partial != null) return SelectChoice(option: partial, how: 'label-contains');
  }

  if (value != null && usable.isNotEmpty) {
    throw _noOption('没有 value 为「$value」的选项', options);
  }
  throw _noOption('没有匹配「${label ?? value ?? ''}」的选项', options);
}

ControlException _noOption(String message, List<SelectOption> options) =>
    ControlException(
      ControlErrorCode.notFound,
      message,
      hint: options.isEmpty
          ? '这个下拉框现在没有选项，可能需要先选上层的条件'
          : '可用选项：${options.take(12).map((option) => option.label).join(' / ')}',
      details: {
        'options': [
          for (final option in options.take(30))
            {'index': option.index, 'value': option.value, 'label': option.label},
        ],
      },
    );
