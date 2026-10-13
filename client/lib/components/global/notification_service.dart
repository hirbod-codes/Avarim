import 'dart:async';

import 'package:avarim/api/root_navigator_key.dart';
import 'package:avarim/components/button.dart';
import 'package:avarim/theme/app_colors.dart';
import 'package:flutter/material.dart';

enum _NotificationType { error, success }

class _NotificationItem {
  final Object id = UniqueKey();
  final _NotificationType type;
  final String message;
  final Duration duration;
  Timer? timer;

  _NotificationItem({required this.type, required this.message, required this.duration});
}

/// Single persistent overlay entry that owns an ordered stack of
/// notifications. New ones are inserted at the top and push existing
/// ones down; removing one (via timer or the close button) collapses
/// its slot and the rest slide up to fill the gap — AnimatedList
/// handles both the insert/remove animation and the reflow for us.
class _NotificationOverlay extends StatefulWidget {
  const _NotificationOverlay({super.key});

  @override
  State<_NotificationOverlay> createState() => _NotificationOverlayState();
}

class _NotificationOverlayState extends State<_NotificationOverlay> {
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  final List<_NotificationItem> _items = [];

  void add(_NotificationItem item) {
    _items.insert(0, item);
    _listKey.currentState?.insertItem(0, duration: const Duration(milliseconds: 300));

    item.timer = Timer(item.duration, () => remove(item));
  }

  void remove(_NotificationItem item) {
    final index = _items.indexOf(item);
    // Guards the same race the old per-entry dismiss() guarded: the
    // timer and the close button can both fire for the same item,
    // whichever loses becomes a safe no-op instead of a bad index.
    if (index == -1) return;

    item.timer?.cancel();
    _items.removeAt(index);
    _listKey.currentState?.removeItem(index, (context, animation) => _buildItem(context, item, animation), duration: const Duration(milliseconds: 250));
  }

  Widget _buildItem(BuildContext context, _NotificationItem item, Animation<double> animation) {
    final theme = Theme.of(context);

    final isError = item.type == _NotificationType.error;
    final background = isError ? theme.colorScheme.error : theme.extension<AppColors>()!.success;
    final foreground = isError ? theme.colorScheme.onError : theme.extension<AppColors>()!.onSuccess;
    final colorName = isError ? theme.colorScheme.onError : theme.extension<AppColors>()!.onSuccess;

    return SizeTransition(
      sizeFactor: animation,
      // ignore: deprecated_member_use
      axisAlignment: -1,
      child: SlideTransition(
        // New items slide down from above into their slot.
        position: Tween<Offset>(begin: const Offset(0, -0.3), end: Offset.zero).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        child: FadeTransition(
          opacity: animation,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              color: background,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(item.message, style: TextStyle(color: foreground)),
                    ),
                    Button(type: ButtonType.text, icon: Icons.close, color: colorName, onPressed: () => remove(item)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 16,
      left: 16,
      right: 16,
      child: AnimatedList(
        key: _listKey,
        shrinkWrap: true,
        initialItemCount: 0,
        itemBuilder: (context, index, animation) => _buildItem(context, _items[index], animation),
      ),
    );
  }
}

class NotificationService {
  static OverlayEntry? _entry;
  static final GlobalKey<_NotificationOverlayState> _overlayKey = GlobalKey<_NotificationOverlayState>();

  static OverlayState? _resolveOverlay(BuildContext context) {
    return Overlay.maybeOf(context) ?? rootNavigatorKey.currentState?.overlay;
  }

  static void _ensureOverlayInserted(BuildContext context) {
    if (_entry != null) return;

    final overlay = _resolveOverlay(context);
    if (overlay == null) return;

    _entry = OverlayEntry(builder: (_) => _NotificationOverlay(key: _overlayKey));
    overlay.insert(_entry!);
  }

  static void _show({BuildContext? context, required String message, required _NotificationType type, Duration? duration}) {
    context ??= rootContext;

    if (context == null) return;

    _ensureOverlayInserted(context);

    _overlayKey.currentState?.add(_NotificationItem(type: type, message: message, duration: duration ?? const Duration(seconds: 12)));
  }

  static void showError({BuildContext? context, required String message, Duration? duration}) {
    _show(context: context, message: message, type: _NotificationType.error, duration: duration);
  }

  static void showSuccess({BuildContext? context, required String message, Duration? duration}) {
    _show(context: context, message: message, type: _NotificationType.success, duration: duration);
  }
}
