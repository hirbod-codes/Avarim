// plan_locked_widgets.dart
//
// Visual + interaction pattern for "this is plan-gated" UI:
//   - PlanLocked: wraps ANY widget (button, card, toggle...) — dims it,
//     adds a small lock badge, and swaps its normal interaction for a
//     tap that opens the upgrade dialog instead.
//   - PlanOption / showPlanOptionSheet: a select-style picker (bottom
//     sheet of options) where individual options can be isLocked. Locked
//     options stay visible (so the user knows the feature exists) but
//     dimmed with a lock icon, and tapping one shows the upgrade
//     dialog instead of selecting it.
//
// Built custom rather than on DropdownButton/ListTile's `enabled` flag
// because Flutter's built-in "disabled" state also swallows the tap —
// there's no way to intercept it to show an upsell message. Here every
// item's tap always fires; what it does depends on `isLocked`.

import 'package:avarim/account/models/user_info.dart';
import 'package:avarim/account/user_info_notifier.dart';
import 'package:avarim/plan/components/upgrade_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Wraps [child] and, if [isLocked], dims it and redirects any tap to the
/// upgrade dialog instead of the widget's normal behavior.
///
/// Usage:
///   PlanLocked(
///     isLocked: !userInfo.hasFeature('bulk_export'),
///     reason: "Bulk export needs the Pro plan.",
///     child: ExportAllButton(),
///   )
class PlanLocked extends ConsumerWidget {
  final bool Function(UserInfo? ui) isLocked;
  final Widget child;
  final String? reason;

  /// Where the lock badge sits. Defaults to top-right, good for
  /// buttons/cards. Set to null to omit the badge (e.g. for small
  /// inline controls where a badge would overlap awkwardly).
  final Alignment? badgeAlignment;

  const PlanLocked({super.key, required this.isLocked, required this.child, this.reason, this.badgeAlignment = Alignment.topRight});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(userInfoProvider).info;
    final locked = isLocked(ui);
    if (!locked) return child;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showUpgradeDialog(context, reason: reason),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // IgnorePointer so the real child never receives the tap
          // (its own onPressed/onTap etc. would otherwise still fire).
          IgnorePointer(
            child: Opacity(
              opacity: 0.45,
              child: ColorFiltered(
                colorFilter: const ColorFilter.matrix(<double>[
                  0.2126,
                  0.7152,
                  0.0722,
                  0,
                  0,
                  0.2126,
                  0.7152,
                  0.0722,
                  0,
                  0,
                  0.2126,
                  0.7152,
                  0.0722,
                  0,
                  0,
                  0,
                  0,
                  0,
                  1,
                  0,
                ]), // greyscale
                child: child,
              ),
            ),
          ),
          if (badgeAlignment != null)
            Positioned(
              top: badgeAlignment == Alignment.topRight ? -6 : null,
              right: badgeAlignment == Alignment.topRight ? -6 : null,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  shape: BoxShape.circle,
                  boxShadow: const [BoxShadow(blurRadius: 2, color: Colors.black26)],
                ),
                child: Icon(Icons.lock, size: 14, color: Theme.of(context).colorScheme.primary),
              ),
            ),
        ],
      ),
    );
  }
}

/// One entry in a plan-aware option list/select.
class PlanOption<T> {
  final T value;
  final String label;
  final IconData? icon;
  final bool locked;
  final String? lockedReason;

  const PlanOption({required this.value, required this.label, this.icon, this.locked = false, this.lockedReason});
}

/// Shows a modal bottom sheet of [options]. Tapping an unlocked option
/// pops the sheet with that value; tapping a locked one opens the
/// upgrade dialog and leaves the sheet open. Use in place of a
/// DropdownButton wherever some choices are plan-gated:
///
///   final chosen = await showPlanOptionSheet<ExportFormat>(
///     context,
///     title: 'Export format',
///     options: [
///       PlanOption(value: ExportFormat.csv, label: 'CSV'),
///       PlanOption(
///         value: ExportFormat.pdf,
///         label: 'PDF',
///         icon: Icons.picture_as_pdf,
///         locked: !userInfo.hasFeature('pdf_export'),
///         lockedReason: 'PDF export needs the Pro plan.',
///       ),
///     ],
///   );
Future<T?> showPlanOptionSheet<T>(BuildContext context, {required List<PlanOption<T>> options, String? title}) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(title, style: Theme.of(sheetContext).textTheme.titleMedium),
            ),
          ...options.map((option) => _PlanOptionTile<T>(option: option)),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// A real inline `DropdownButton` (no modal/sheet) where some options
/// are plan-gated. Every item stays tappable so the button behaves
/// like a normal dropdown — Flutter's own `enabled: false` on
/// DropdownMenuItem would make locked items untappable, which is
/// exactly what we DON'T want (there'd be no way to trigger the
/// upgrade dialog). Instead the lock check happens in [onChanged]:
/// picking a locked option reopens... actually just declines the
/// selection and shows the dialog, leaving [value] unchanged.
///
/// Controlled component, same shape as DropdownButton itself:
///
///   PlanDropdown<ExportFormat>(
///     value: selectedFormat,
///     options: [
///       PlanOption(value: ExportFormat.csv, label: 'CSV'),
///       PlanOption(
///         value: ExportFormat.pdf,
///         label: 'PDF',
///         icon: Icons.picture_as_pdf,
///         locked: !userInfo.hasFeature('pdf_export'),
///         lockedReason: 'PDF export needs the Pro plan.',
///       ),
///     ],
///     onChanged: (format) => setState(() => selectedFormat = format),
///   )
class PlanDropdown<T> extends StatelessWidget {
  final T? value;
  final List<PlanOption<T>> options;
  final ValueChanged<T> onChanged;
  final String? hint;

  const PlanDropdown({super.key, required this.value, required this.options, required this.onChanged, this.hint});

  @override
  Widget build(BuildContext context) {
    final dimColor = Theme.of(context).disabledColor;

    return DropdownButton<T>(
      value: value,
      hint: hint == null ? null : Text(hint!),
      items: options.map((option) {
        return DropdownMenuItem<T>(
          value: option.value,
          // Deliberately left enabled (the default) for every item,
          // locked or not — see the class doc above.
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (option.icon != null) ...[Icon(option.icon, size: 18, color: option.locked ? dimColor : null), const SizedBox(width: 8)],
              Text(option.label, style: TextStyle(color: option.locked ? dimColor : null)),
              if (option.locked) ...[const SizedBox(width: 8), Icon(Icons.lock, size: 14, color: dimColor)],
            ],
          ),
        );
      }).toList(),
      onChanged: (selected) {
        if (selected == null) return;
        final option = options.firstWhere((o) => o.value == selected);
        if (option.locked) {
          showUpgradeDialog(context, reason: option.lockedReason);
          return; // value prop is unchanged, so the button visually reverts
        }
        onChanged(selected);
      },
    );
  }
}

class _PlanOptionTile<T> extends StatelessWidget {
  final PlanOption<T> option;

  const _PlanOptionTile({required this.option});

  @override
  Widget build(BuildContext context) {
    final dimColor = Theme.of(context).disabledColor;

    return ListTile(
      leading: option.icon == null ? null : Icon(option.icon, color: option.locked ? dimColor : null),
      title: Text(option.label, style: TextStyle(color: option.locked ? dimColor : null)),
      trailing: option.locked ? Icon(Icons.lock, size: 18, color: dimColor) : null,
      onTap: () {
        if (option.locked) {
          showUpgradeDialog(context, reason: option.lockedReason);
        } else {
          Navigator.of(context).pop(option.value);
        }
      },
    );
  }
}
