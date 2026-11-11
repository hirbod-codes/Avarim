import 'package:flutter/widgets.dart';

/// A box whose width and height are each given either as a percent of the
/// parent's available space or as a plain number of logical pixels.
///
/// Inputs (all optional):
/// - [widthPercent] / [heightPercent]: percent in (0, 100] of the parent's
///   maximum width / height, e.g. `54`.
/// - [width] / [height]: a fixed size in logical pixels.
///
/// For each axis give the percent or the number, not both. An axis with
/// neither defaults to the maximum (100% of the parent).
///
/// Like [SizedBox], [child] is forced to the box's size, and a fixed size
/// larger than the parent allows is clamped to the parent.
///
/// A percent (including the 100% default) is relative to the parent's maximum
/// extent. Where the parent gives no bound on an axis (the height inside a
/// [Column] or a scroll view, the width inside a [Row]) there is nothing to
/// take a percent of, so the box fits its child on that axis. A fixed number
/// still applies. Wrap the box in [Expanded] inside a [Column] or [Row] to
/// give it a bounded axis.
///
/// When the parent forces an exact size (e.g. [Expanded], or a [SizedBox]
/// parent), percentages are taken of that size and the box sits at the
/// top-start corner of it.
///
/// Note: this widget uses a [LayoutBuilder], so it can't be placed where
/// intrinsic sizes are requested (inside [IntrinsicHeight], [IntrinsicWidth]).
class RelativeBox extends StatelessWidget {
  const RelativeBox({super.key, this.width, this.height, this.widthPercent, this.heightPercent, this.child})
    : assert(width == null || widthPercent == null, 'Specify either width or widthPercent, not both'),
      assert(height == null || heightPercent == null, 'Specify either height or heightPercent, not both'),
      assert(width == null || width >= 0, 'width must be >= 0'),
      assert(height == null || height >= 0, 'height must be >= 0'),
      assert(widthPercent == null || (widthPercent > 0 && widthPercent <= 100), 'widthPercent must be in (0, 100]'),
      assert(heightPercent == null || (heightPercent > 0 && heightPercent <= 100), 'heightPercent must be in (0, 100]');

  /// Fixed width in logical pixels.
  final double? width;

  /// Fixed height in logical pixels.
  final double? height;

  /// Width as a percent of the parent's maximum width.
  final double? widthPercent;

  /// Height as a percent of the parent's maximum height.
  final double? heightPercent;

  final Widget? child;

  static double? _resolve(double? fixed, double? percent, double max) {
    if (fixed != null) return fixed;
    if (!max.isFinite) return null; // unbounded: nothing to take a percent of
    return max * (percent ?? 100) / 100;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final resolvedWidth = _resolve(width, widthPercent, constraints.maxWidth);
        final resolvedHeight = _resolve(height, heightPercent, constraints.maxHeight);

        // Align loosens the incoming constraints so the sizes still apply
        // under tight parents, and (with factors of 1) reports exactly the
        // box's size under loose ones.
        return Align(
          alignment: AlignmentDirectional.topStart,
          widthFactor: 1,
          heightFactor: 1,
          child: SizedBox(width: resolvedWidth, height: resolvedHeight, child: child),
        );
      },
    );
  }
}
