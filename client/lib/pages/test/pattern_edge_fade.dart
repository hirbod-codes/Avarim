import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';

import 'geometric_pattern.dart';

enum FadeEdge { top, bottom, left, right }

/// Shows a pattern as a soft band along the edges of its area.
///
/// Opacity as a function of the distance `d` from the nearest edge:
///
/// ```
/// 1 |          ______
///   |        /        \
///   |      /            \
/// 0 |____/                \_______________  (towards the middle)
///   0   edgeFade  +hold   +fadeExtent
/// ```
///
/// * `edgeFade`  – distance over which it grows from 0 (at the edge) to full,
///                 shaped by `edgeCurve`. Leave at 0 for "full at the edge".
/// * `hold`      – distance it stays at full strength.
/// * `fadeExtent`– distance over which it fades back to 0 going inwards,
///                 shaped by `fadeCurve`.
///
/// ```dart
/// PatternEdgeFade(
///   colors: PatternColors.fromScheme(Theme.of(context).colorScheme),
///   edgeFade: 70,
///   edgeCurve: Curves.easeOut,
///   hold: 30,
///   fadeExtent: 150,
///   fadeCurve: Curves.easeIn,
///   child: Center(child: MyContent()),
/// )
/// ```
///
/// Implementation: one pattern strip per edge, each masked with a gradient and
/// clipped to a mitred (picture-frame) trapezoid, so the strips never overlap
/// and the opacity is exact everywhere, including the corners. All strips share
/// one tile grid, so the pattern stays continuous around the corners.
class PatternEdgeFade extends StatelessWidget {
  const PatternEdgeFade({
    super.key,
    this.colors = const PatternColors(),
    this.tileSize = 280,
    this.edgeFade = 0,
    this.hold = 0,
    this.fadeExtent = 180,
    this.maxOpacity = 1,
    this.edgeCurve = Curves.easeInOut,
    this.fadeCurve = Curves.easeInOut,
    this.edges = const {FadeEdge.top, FadeEdge.bottom, FadeEdge.left, FadeEdge.right},
    this.offset = Offset.zero,
    this.patternBuilder,
    this.child,
    required this.assetPath,
  }) : assert(edgeFade >= 0),
       assert(hold >= 0),
       assert(fadeExtent > 0);

  /// Colours for the bundled pattern (ignored if [patternBuilder] is set).
  final PatternColors colors;

  /// Width of one pattern repeat in logical px.
  final double tileSize;

  /// Px from the edge over which the pattern grows from 0 to full strength.
  final double edgeFade;

  /// Px the pattern stays at full strength.
  final double hold;

  /// Px over which it fades from full strength back to 0, going inwards.
  final double fadeExtent;

  /// Peak opacity (0..1).
  final double maxOpacity;

  /// Easing of the ramp-up from the edge (0 -> full). Progress 0..1 is the
  /// position within [edgeFade]; the output is the opacity (before
  /// [maxOpacity]). `easeIn` starts slowly, `easeOut` appears quickly.
  final Curve edgeCurve;

  /// Easing of the fade-out going inwards (full -> 0). Progress 0..1 is the
  /// position within [fadeExtent]; opacity is `1 - fadeCurve(progress)`.
  /// `easeIn` stays strong for longer then drops; `easeOut` drops quickly then
  /// lingers faintly.
  final Curve fadeCurve;

  /// Which edges show the pattern.
  final Set<FadeEdge> edges;

  /// Shifts the pattern grid.
  final Offset offset;

  /// Use another pattern. It receives the grid offset it MUST forward, e.g.
  /// `(o) => TiledSvg.asset('assets/x.svg', offset: o, tileSize: 200)`.
  final Widget Function(Offset gridOffset)? patternBuilder;

  /// Drawn on top of the pattern.
  final Widget? child;

  double get _band => edgeFade + hold + fadeExtent;

  double _alphaAt(double d) {
    double a;
    if (d < edgeFade) {
      a = edgeCurve.transform((d / edgeFade).clamp(0.0, 1.0));
    } else if (d <= edgeFade + hold) {
      a = 1;
    } else {
      a = 1 - fadeCurve.transform(((d - edgeFade - hold) / fadeExtent).clamp(0.0, 1.0));
    }
    return (a * maxOpacity).clamp(0.0, 1.0);
  }

  final String assetPath;

  Widget _pattern(Offset gridOffset) =>
      patternBuilder?.call(gridOffset) ?? GeometricPattern(colors: colors, tileSize: tileSize, offset: gridOffset, assetPath: assetPath);

  /// [length] is the strip's thickness; the gradient runs from the outer edge
  /// ([from]) inwards ([to]).
  Widget _strip(Rect rect, double length, Alignment from, Alignment to, List<Offset> localPolygon) {
    // Sample the profile densely, plus the exact breakpoints.
    final ds = <double>{0, length};
    const n = 24;
    for (var i = 0; i <= n; i++) {
      ds.add(length * i / n);
    }
    for (final b in [edgeFade, edgeFade + hold]) {
      if (b > 0 && b < length) ds.add(b);
    }
    final sorted = ds.toList()..sort();
    final colorsList = [for (final d in sorted) Color.fromRGBO(0, 0, 0, _alphaAt(d))];
    final stops = [for (final d in sorted) d / length];

    return Positioned.fromRect(
      rect: rect,
      child: ClipPath(
        clipper: _PolygonClipper(localPolygon),
        clipBehavior: Clip.hardEdge, // adjacent strips match, so no seam shows
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => LinearGradient(begin: from, end: to, colors: colorsList, stops: stops).createShader(bounds),
          // Offsetting by the strip's position keeps every strip on the same
          // global grid, so the pattern lines up across the corners.
          child: _pattern(rect.topLeft + offset),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: LayoutBuilder(
                builder: (context, box) {
                  final fb = MediaQuery.sizeOf(context);
                  final w = box.hasBoundedWidth ? box.maxWidth : fb.width;
                  final h = box.hasBoundedHeight ? box.maxHeight : fb.height;
                  // One thickness for all edges keeps the corner joins at 45°.
                  final l = math.min(_band, math.min(w, h) / 2);

                  return Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      if (edges.contains(FadeEdge.top))
                        _strip(Rect.fromLTWH(0, 0, w, l), l, Alignment.topCenter, Alignment.bottomCenter, [
                          const Offset(0, 0),
                          Offset(w, 0),
                          Offset(w - l, l),
                          Offset(l, l),
                        ]),
                      if (edges.contains(FadeEdge.bottom))
                        _strip(Rect.fromLTWH(0, h - l, w, l), l, Alignment.bottomCenter, Alignment.topCenter, [
                          Offset(l, 0),
                          Offset(w - l, 0),
                          Offset(w, l),
                          Offset(0, l),
                        ]),
                      if (edges.contains(FadeEdge.left))
                        _strip(Rect.fromLTWH(0, 0, l, h), l, Alignment.centerLeft, Alignment.centerRight, [
                          const Offset(0, 0),
                          Offset(l, l),
                          Offset(l, h - l),
                          Offset(0, h),
                        ]),
                      if (edges.contains(FadeEdge.right))
                        _strip(Rect.fromLTWH(w - l, 0, l, h), l, Alignment.centerRight, Alignment.centerLeft, [
                          Offset(l, 0),
                          Offset(l, h),
                          Offset(0, h - l),
                          Offset(0, l),
                        ]),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        if (child != null) child!,
      ],
    );
  }
}

class _PolygonClipper extends CustomClipper<Path> {
  _PolygonClipper(this.points);
  final List<Offset> points;

  @override
  Path getClip(Size size) => Path()..addPolygon(points, true);

  @override
  bool shouldReclip(_PolygonClipper old) => !listEquals(old.points, points);
}
