import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Overlays a woven-cloth texture on [child] (a pattern, usually).
///
/// * **Thread grain** - fine warp/weft lines snapped to whole device pixels, so
///   they stay crisp and never produce moiré at any tile size or zoom.
/// * **Folds** (optional) - soft diagonal light/dark bands, like cloth hanging
///   in gentle folds.
///
/// ```dart
/// FabricTexture(
///   child: GeometricPattern(assetPath: '...fabric.svg', colors: colors),
/// )
/// ```
///
/// Don't enable [folds] inside `PatternEdgeFade.patternBuilder`: each edge
/// strip would get its own folds and the joins would show. Wrap the whole
/// `PatternEdgeFade` instead, or keep [folds] at 0 there.
class FabricTexture extends StatelessWidget {
  const FabricTexture({
    super.key,
    required this.child,
    this.threadSpacing = 3,
    this.threadOpacity = 0.06,
    this.folds = 0,
    this.foldCount = 3,
    this.foldAngle = 0.6,
  }) : assert(threadSpacing > 0),
       assert(foldCount > 0);

  final Widget child;

  /// Distance between threads in logical px (rounded to whole device px).
  final double threadSpacing;

  /// Strength of the thread grain, 0..1. 0.04-0.09 is subtle; 0 turns it off.
  final double threadOpacity;

  /// Strength of the folds, 0..1. 0 (default) = none.
  final double folds;

  /// How many light/dark fold pairs cross the widget.
  final int foldCount;

  /// Direction the folds run across, in radians.
  final double foldAngle;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _FabricPainter(spacing: threadSpacing, opacity: threadOpacity, dpr: dpr, folds: folds, foldCount: foldCount, foldAngle: foldAngle),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FabricPainter extends CustomPainter {
  _FabricPainter({required this.spacing, required this.opacity, required this.dpr, required this.folds, required this.foldCount, required this.foldAngle});

  final double spacing, opacity, dpr, folds, foldAngle;
  final int foldCount;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    if (folds > 0) {
      final dx = math.cos(foldAngle), dy = math.sin(foldAngle);
      final half = (size.width * dx.abs() + size.height * dy.abs()) / 2;
      final c = size.center(Offset.zero);
      final samples = foldCount * 12;
      final colors = <Color>[];
      final stops = <double>[];
      for (var i = 0; i <= samples; i++) {
        final t = i / samples;
        final v = math.sin(t * foldCount * 2 * math.pi);
        final a = (v.abs() * 0.10 * folds).clamp(0.0, 1.0);
        colors.add(v >= 0 ? Color.fromRGBO(255, 255, 255, a) : Color.fromRGBO(0, 0, 0, a));
        stops.add(t);
      }
      canvas.drawRect(rect, Paint()..shader = ui.Gradient.linear(c - Offset(dx, dy) * half, c + Offset(dx, dy) * half, colors, stops));
    }

    if (opacity > 0) {
      final px = 1 / dpr; // one device pixel in logical px
      final step = (spacing * dpr).round().clamp(2, 64) * px;

      final warp = <double>[]; // vertical threads
      for (var x = px / 2; x < size.width; x += step) {
        warp
          ..add(x)
          ..add(0)
          ..add(x)
          ..add(size.height);
      }
      final weft = <double>[]; // horizontal threads
      for (var y = px / 2; y < size.height; y += step) {
        weft
          ..add(0)
          ..add(y)
          ..add(size.width)
          ..add(y);
      }

      canvas.drawRawPoints(
        ui.PointMode.lines,
        Float32List.fromList(warp),
        Paint()
          ..isAntiAlias = false
          ..strokeWidth = px
          ..color = Color.fromRGBO(0, 0, 0, opacity),
      );
      canvas.drawRawPoints(
        ui.PointMode.lines,
        Float32List.fromList(weft),
        Paint()
          ..isAntiAlias = false
          ..strokeWidth = px
          ..color = Color.fromRGBO(255, 255, 255, opacity * 0.8),
      );
    }
  }

  @override
  bool shouldRepaint(_FabricPainter o) =>
      o.spacing != spacing || o.opacity != opacity || o.dpr != dpr || o.folds != folds || o.foldCount != foldCount || o.foldAngle != foldAngle;
}
