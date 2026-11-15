import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../config/app_tokens.dart';
import '../../services/haptic_service.dart';

/// One row in any list: settings, history, prompts, sites.
///
/// The app had four list shapes — a settings row, a history tile, a shortcut
/// tile, a tab card — each with its own height, its own icon slot and its own
/// chevron. Rows are the most repeated element in the product, so they are the
/// cheapest place to buy consistency: one height, one icon slot, one place for
/// the right-hand action.
///
/// 56dp is not arbitrary. It is the smallest row that a thumb hits without
/// aiming, and it is what the platform's own settings app uses.
class OperonListRow extends StatelessWidget {
  const OperonListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.danger = false,
    this.showChevron = true,
    this.padding,
    this.minHeight,
    this.titleStyle,
    this.leadingSize = 32,
    this.leadingGap = AppSpace.x3,
  });

  final String title;
  final String? subtitle;

  /// A [SiteIcon], an icon, an avatar — anything square where a mark belongs.
  /// Sits in a fixed slot so titles line up across rows.
  final Widget? leading;
  final Widget? trailing;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Destructive rows are red and cannot be tapped by accident.
  final bool danger;

  /// A row that navigates says so; a row that only holds a value does not.
  final bool showChevron;

  final EdgeInsetsGeometry? padding;
  final double? minHeight;
  final TextStyle? titleStyle;
  final double leadingSize;
  final double leadingGap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dangerInk = AppTheme.dangerOf(isDark);
    final ink = danger ? dangerInk : AppInk.primary(isDark);
    final sub = danger
        ? dangerInk.withValues(alpha: 0.75)
        : AppInk.secondary(isDark);

    final resolvedTitleStyle = (titleStyle ??
            AppType.body.copyWith(fontWeight: FontWeight.w500))
        .copyWith(color: ink);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight ?? AppSpace.row),
          child: Padding(
            padding: padding ??
                const EdgeInsets.symmetric(horizontal: AppSpace.page),
            child: Row(
              children: [
                if (leading != null) ...[
                  SizedBox(
                    width: leadingSize,
                    height: leadingSize,
                    child: Center(child: leading),
                  ),
                  SizedBox(width: leadingGap),
                ],
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: resolvedTitleStyle,
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.caption.copyWith(
                            color: sub,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: AppSpace.x2),
                  trailing!,
                ],
                if (showChevron) ...[
                  const SizedBox(width: AppSpace.x1),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppInk.tertiary(isDark),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One choice inside [showOperonOptionSheet] / [OperonOptionRow].
class OperonOptionItem<T> {
  final T value;
  final String label;
  final String? subtitle;
  final IconData? icon;

  const OperonOptionItem({
    required this.value,
    required this.label,
    this.subtitle,
    this.icon,
  });
}

/// Shows a compact native-feeling bottom sheet selector instead of a bulky
/// Material form dropdown.
Future<T?> showOperonOptionSheet<T>({
  required BuildContext context,
  required String title,
  required List<OperonOptionItem<T>> options,
  required T selected,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) {
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      final sheetBg = isDark ? AppTheme.darkCard : AppTheme.lightCard;
      final hairline = AppInk.hairline(isDark);
      final accent = AppTheme.accentOf(isDark);

      return Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.7,
        ),
        decoration: BoxDecoration(
          color: sheetBg,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
          border: Border(
            top: BorderSide(color: hairline, width: AppStroke.hairline),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(
                    top: AppSpace.x2 + 2,
                    bottom: AppSpace.x1,
                  ),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.page,
                  AppSpace.x2,
                  AppSpace.page,
                  AppSpace.x2,
                ),
                child: Text(
                  title,
                  style: AppType.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppInk.primary(isDark),
                  ),
                ),
              ),
              Divider(height: 1, thickness: AppStroke.hairline, color: hairline),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.x1),
                  itemCount: options.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    thickness: AppStroke.hairline,
                    indent: AppSpace.page,
                    endIndent: AppSpace.page,
                    color: hairline,
                  ),
                  itemBuilder: (itemCtx, index) {
                    final item = options[index];
                    final isSelected = item.value == selected;
                    return OperonListRow(
                      title: item.label,
                      subtitle: item.subtitle,
                      minHeight: 46,
                      showChevron: false,
                      titleStyle: AppType.label.copyWith(
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: isSelected ? accent : AppInk.primary(isDark),
                      ),
                      leading: item.icon != null
                          ? Icon(
                              item.icon,
                              size: 18,
                              color: isSelected
                                  ? accent
                                  : AppInk.secondary(isDark),
                            )
                          : null,
                      leadingSize: 28,
                      leadingGap: AppSpace.x2,
                      trailing: isSelected
                          ? Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: accent,
                            )
                          : null,
                      onTap: () {
                        HapticService.selection();
                        Navigator.of(itemCtx).pop(item.value);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Compact single-line settings picker row (`label` on the left, current choice
/// and chevron on the right) that opens [showOperonOptionSheet] when tapped.
class OperonOptionRow<T> extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final T value;
  final String? valueLabel;
  final List<OperonOptionItem<T>> options;
  final ValueChanged<T> onChanged;
  final EdgeInsetsGeometry? padding;
  final double minHeight;

  const OperonOptionRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    required this.value,
    this.valueLabel,
    required this.options,
    required this.onChanged,
    this.padding,
    this.minHeight = 46,
  });

  String _resolvedLabel() {
    if (valueLabel != null) return valueLabel!;
    for (final item in options) {
      if (item.value == value) return item.label;
    }
    return '$value';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return OperonListRow(
      title: title,
      subtitle: subtitle,
      leading: leading,
      minHeight: minHeight,
      padding: padding,
      titleStyle: AppType.label.copyWith(
        fontWeight: FontWeight.w500,
        color: AppInk.primary(isDark),
      ),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 168),
        child: Text(
          _resolvedLabel(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.right,
          style: AppType.caption.copyWith(
            color: AppInk.secondary(isDark),
          ),
        ),
      ),
      onTap: () async {
        HapticService.light();
        final picked = await showOperonOptionSheet<T>(
          context: context,
          title: title,
          options: options,
          selected: value,
        );
        if (picked != null && picked != value) {
          onChanged(picked);
        }
      },
    );
  }
}
