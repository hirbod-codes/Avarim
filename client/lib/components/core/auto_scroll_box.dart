import 'package:flutter/widgets.dart';

/// Fills all the space its parent offers, and scrolls vertically only when
/// [child] is taller than that space.
///
/// If [child] is shorter, it is laid out at the top of the box and nothing
/// scrolls. If it is taller, the box scrolls.
///
/// Where the parent gives no bound on an axis (the width inside a [Row], or
/// the height inside another scroll view), there is no "maximum" to fill, so
/// the box fits its child on that axis instead. This is also what makes
/// nesting work: an [AutoScrollBox] inside another one just grows, and the
/// outer one does the scrolling.
///
/// Children
/// - Any ordinary widget (Column, Text, Image, Container, another
///   [AutoScrollBox], ...) works as-is.
/// - If [child] is itself a [ScrollView] (ListView, GridView,
///   CustomScrollView), it simply fills the box and scrolls by itself, so
///   [controller] and [physics] are not applied to it.
/// - A list buried deeper inside [child] (e.g. inside a Column) has unbounded
///   height to work with, which Flutter cannot lay out for a lazy list. Give
///   that inner list `shrinkWrap: true` and
///   `physics: NeverScrollableScrollPhysics()`, or put it in a bounded
///   parent such as a SizedBox.
class AutoScrollBox extends StatelessWidget {
  const AutoScrollBox({super.key, required this.child, this.controller, this.physics});

  final Widget child;

  /// Controller of the internal vertical scroll view.
  final ScrollController? controller;

  /// Scroll physics of the internal vertical scroll view.
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth ? constraints.maxWidth : null;
        final height = constraints.hasBoundedHeight ? constraints.maxHeight : null;

        final Widget content = child is ScrollView
            ? child
            : SingleChildScrollView(
                controller: controller,
                physics: physics,
                // Make the child at least as tall as the box, so children
                // that want to fill it (Center, a colored Container, ...)
                // behave. Taller children push past it and scroll.
                child: height == null
                    ? child
                    : ConstrainedBox(
                        constraints: BoxConstraints(minHeight: height),
                        child: child,
                      ),
              );

        return SizedBox(width: width, height: height, child: content);
      },
    );
  }
}
