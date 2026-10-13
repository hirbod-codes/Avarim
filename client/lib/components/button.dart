import 'dart:math';

import 'package:avarim/theme/theme_radius.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ButtonType { elevated, text, outlined, floatingAction }

enum ButtonVariant { filled, outline, ghost }

class Button extends ConsumerWidget {
  final String? label;
  final VoidCallback? onPressed;

  final ButtonType type;
  final bool isTransparent;
  Color? color;
  Color? onColor;

  final bool isLoading;
  final IconData? icon;

  final double? width;
  final double? height;

  final double radius;
  final RoundedRectangleBorder? shape;

  final double iconSize;

  // ignore: prefer_const_constructors_in_immutables
  Button({
    super.key,
    this.label,
    this.onPressed,
    this.type = ButtonType.elevated,
    this.isTransparent = false,
    this.isLoading = false,
    this.icon,
    this.iconSize = 18,
    this.width,
    this.height,
    this.radius = AppRadius.md,
    this.shape,
    this.color,
    this.onColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    color ??= theme.colorScheme.primary;

    switch (type) {
      case ButtonType.elevated:
        final baseColor = isTransparent ? Colors.transparent : (color!);
        onColor ??= _getColor(theme, color!);
        return _elevated(baseColor, onColor!);
      case ButtonType.floatingAction:
        final baseColor = isTransparent ? Colors.transparent : (color!);
        onColor ??= _getColor(theme, color!);
        return _fab(baseColor, onColor!);
      case ButtonType.text:
        final baseColor = isTransparent ? Colors.transparent : (color!);
        return _text(baseColor);
      case ButtonType.outlined:
        final baseColor = isTransparent ? Colors.transparent : (color!);
        return _outlined(baseColor);
    }
  }

  Widget _elevated(Color baseColor, Color fg) {
    return SizedBox(
      width: width,
      height: height,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(backgroundColor: baseColor, foregroundColor: fg, shape: shape ?? _shape()),
        child: _child(textColor: fg),
      ),
    );
  }

  Widget _outlined(Color baseColor) {
    return SizedBox(
      width: width,
      height: height,
      child: OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          fixedSize: width != null && height != null ? Size(width!, height!) : null,
          foregroundColor: baseColor,
          side: BorderSide(color: baseColor, width: 1),
          shape: shape ?? _shape(),
        ),
        child: _child(textColor: baseColor),
      ),
    );
  }

  Widget _text(Color baseColor) {
    return SizedBox(
      width: width,
      height: height,
      child: TextButton(
        onPressed: isLoading ? null : onPressed,
        style: TextButton.styleFrom(foregroundColor: baseColor, shape: label == null && icon != null ? CircleBorder() : shape ?? _shape()),
        child: _child(textColor: baseColor),
      ),
    );
  }

  Widget _fab(Color baseColor, Color fg) {
    return FloatingActionButton(
      onPressed: isLoading ? null : onPressed,
      backgroundColor: baseColor,
      foregroundColor: fg,
      child: isLoading
          ? SizedBox(
              width: width ?? 18,
              height: height ?? 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: fg),
            )
          : (icon != null
                ? Icon(icon, size: min(width ?? double.infinity, iconSize), color: fg)
                : Icon(Icons.add, size: min(width ?? double.infinity, iconSize), color: fg)),
    );
  }

  Widget _child({required Color textColor}) {
    if (isLoading) {
      return SizedBox(
        width: min(width ?? double.infinity, iconSize),
        height: min(width ?? double.infinity, iconSize),
        child: CircularProgressIndicator(strokeWidth: 2, color: textColor),
      );
    }

    if (icon == null) {
      return Text(label ?? "", style: TextStyle(color: textColor));
    }

    List<Widget> children = [Icon(icon, size: min(width ?? double.infinity, iconSize), color: textColor)];
    if (label != null) {
      children.add(const SizedBox(width: 8));
      children.add(Text(label ?? ""));
    }

    return Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: children);
  }

  RoundedRectangleBorder _shape() {
    return RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
  }

  Color _getColor(ThemeData theme, Color color) {
    if (theme.colorScheme.primary == color) return theme.colorScheme.onPrimary;
    if (theme.colorScheme.primaryContainer == color) return theme.colorScheme.onPrimaryContainer;

    if (theme.colorScheme.secondary == color) return theme.colorScheme.onSecondary;
    if (theme.colorScheme.secondaryContainer == color) return theme.colorScheme.onSecondaryContainer;

    if (theme.colorScheme.tertiary == color) return theme.colorScheme.onTertiary;
    if (theme.colorScheme.tertiaryContainer == color) return theme.colorScheme.onTertiaryContainer;

    if (theme.colorScheme.error == color) return theme.colorScheme.onError;
    if (theme.colorScheme.errorContainer == color) return theme.colorScheme.onErrorContainer;

    return theme.colorScheme.onSurface;
  }
}
