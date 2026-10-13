import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';

// ---------------------------------------------------------------------------
// 1. Generic: tile ANY seamless SVG as a background and recolour it
// ---------------------------------------------------------------------------

/// Repeats an SVG as a background, optionally swapping its colours.
///
/// ```dart
/// TiledSvg.asset(
///   'assets/patterns/some_downloaded_pattern.svg',
///   tileSize: 200,
///   colorMap: {
///     const Color(0xFF9C92AC): Colors.teal,   // original -> replacement
///     const Color(0xFFFFFFFF): Colors.black,
///   },
///   child: MyScreen(),
/// )
/// ```
///
/// Use [TiledSvg.detectColors] on the SVG text to find which colours a file
/// uses. The tile is sized from the SVG's `viewBox`, so non-square tiles work.
class TiledSvg extends StatefulWidget {
  const TiledSvg.asset(
    String this.assetPath, {
    super.key,
    this.colorMap = const <Color, Color>{},
    this.tileSize = 280,
    this.opacity = 1,
    this.offset = Offset.zero,
    this.backgroundColor,
    this.child,
  }) : svgString = null,
       assert(tileSize > 0);

  const TiledSvg.string(
    String this.svgString, {
    super.key,
    this.colorMap = const <Color, Color>{},
    this.tileSize = 280,
    this.opacity = 1,
    this.offset = Offset.zero,
    this.backgroundColor,
    this.child,
  }) : assetPath = null,
       assert(tileSize > 0);

  final String? assetPath;
  final String? svgString;

  /// original colour -> replacement. Compared on RGB only; the original
  /// alpha is kept. Colours not listed are left alone.
  final Map<Color, Color> colorMap;

  /// Width of one repeat in logical px (height follows the SVG's aspect ratio).
  final double tileSize;

  /// 0..1, applied to the pattern only (not [child]).
  final double opacity;

  /// Shifts the pattern, e.g. for parallax.
  final Offset offset;

  /// Painted behind the tiles (also shown while the asset loads).
  final Color? backgroundColor;

  final Widget? child;

  /// Hex colours (#rgb / #rrggbb) found in [svg]. Handy for building [colorMap].
  static Set<Color> detectColors(String svg) {
    final out = <Color>{};
    for (final m in RegExp(r'#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b').allMatches(svg)) {
      var h = m[1]!;
      if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
      out.add(Color(0xFF000000 | int.parse(h, radix: 16)));
    }
    return out;
  }

  @override
  State<TiledSvg> createState() => _TiledSvgState();
}

class _TiledSvgState extends State<TiledSvg> {
  static final Map<String, Future<String>> _assetCache = {};
  late Future<String> _svg;

  @override
  void initState() {
    super.initState();
    _svg = _load();
  }

  @override
  void didUpdateWidget(TiledSvg old) {
    super.didUpdateWidget(old);
    if (old.assetPath != widget.assetPath || old.svgString != widget.svgString) {
      _svg = _load();
    }
  }

  Future<String> _load() {
    final s = widget.svgString;
    if (s != null) return Future.value(s);
    return _assetCache.putIfAbsent(widget.assetPath!, () => rootBundle.loadString(widget.assetPath!));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: ColoredBox(
              color: widget.backgroundColor ?? const Color(0x00000000),
              child: FutureBuilder<String>(
                future: _svg,
                builder: (context, snap) {
                  if (snap.hasError) {
                    FlutterError.reportError(
                      FlutterErrorDetails(
                        exception: snap.error!,
                        stack: snap.stackTrace,
                        library: 'TiledSvg',
                        context: ErrorDescription(
                          'while loading ${widget.assetPath ?? 'SVG string'} '
                          '(is it listed under flutter: assets: in pubspec.yaml?)',
                        ),
                      ),
                    );
                  }
                  if (!snap.hasData) return const SizedBox.expand();
                  return Opacity(
                    opacity: widget.opacity.clamp(0.0, 1.0),
                    child: _Grid(
                      svg: snap.data!,
                      tileWidth: widget.tileSize,
                      offset: widget.offset,
                      mapper: widget.colorMap.isEmpty ? null : _RecolorMapper(widget.colorMap),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        if (widget.child != null) widget.child!,
      ],
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.svg, required this.tileWidth, required this.offset, required this.mapper});

  final String svg;
  final double tileWidth;
  final Offset offset;
  final ColorMapper? mapper;

  /// width / height from the root <svg> tag's viewBox (or width/height).
  static double aspectOf(String svg) {
    final tag = RegExp(r'<svg\b[^>]*>', dotAll: true).firstMatch(svg)?[0];
    if (tag == null) return 1;
    final vb = RegExp(r'viewBox\s*=\s*"([^"]+)"').firstMatch(tag)?[1];
    if (vb != null) {
      final p = vb.trim().split(RegExp(r'[\s,]+')).map(double.tryParse).toList();
      if (p.length == 4 && p[2] != null && p[3] != null && p[3]! > 0) {
        return p[2]! / p[3]!;
      }
    }
    double? num(String name) {
      final v = RegExp('\\b$name\\s*=\\s*"([0-9.]+)').firstMatch(tag)?[1];
      return v == null ? null : double.tryParse(v);
    }

    final w = num('width'), h = num('height');
    return (w != null && h != null && h > 0) ? w / h : 1;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.hasBoundedWidth && box.hasBoundedHeight ? box.biggest : MediaQuery.sizeOf(context);

        final tw = tileWidth.roundToDouble();
        final th = (tileWidth / aspectOf(svg)).roundToDouble();
        // Dart's % is never negative for a positive divisor.
        final sx = -(offset.dx % tw);
        final sy = -(offset.dy % th);
        final cols = ((size.width - sx) / tw).ceil();
        final rows = ((size.height - sy) / th).ceil();

        return ClipRect(
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              for (var r = 0; r < rows; r++)
                for (var c = 0; c < cols; c++)
                  Positioned(
                    left: sx + c * tw,
                    top: sy + r * th,
                    // +1px overlap hides anti-aliasing hairlines between tiles.
                    width: tw + 1,
                    height: th + 1,
                    child: SvgPicture.string(svg, fit: BoxFit.fill, colorMapper: mapper),
                  ),
            ],
          ),
        );
      },
    );
  }
}

/// Maps colours while flutter_svg parses the file, so it works however the
/// colour was written (#abc, #aabbcc, rgb(), a name) and also on gradients.
class _RecolorMapper extends ColorMapper {
  _RecolorMapper(Map<Color, Color> map) : _map = {for (final e in map.entries) e.key.toARGB32() & 0xFFFFFF: e.value};

  final Map<int, Color> _map;

  @override
  Color substitute(String? id, String elementName, String attributeName, Color color) {
    final argb = color.toARGB32();
    final to = _map[argb & 0xFFFFFF];
    if (to == null) return color;
    return Color((argb & 0xFF000000) | (to.toARGB32() & 0xFFFFFF));
  }

  // Equality lets flutter_svg reuse its parsed-picture cache across rebuilds.
  @override
  bool operator ==(Object other) => other is _RecolorMapper && mapEquals(other._map, _map);

  @override
  int get hashCode => Object.hashAll(_map.entries.map((e) => Object.hash(e.key, e.value)));
}

// ---------------------------------------------------------------------------
// 2. Preset: the bundled geometric pattern with six named colour roles
// ---------------------------------------------------------------------------

/// The six colour roles in `assets/patterns/geometric_pattern.svg`.
@immutable
class PatternColors {
  const PatternColors({
    this.ground = const Color(0xFF0A2540), // background / gaps
    this.primary = const Color(0xFF1B9FBF), // medallions + swirls
    this.light = const Color(0xFF5FD3DE), // highlights, petals
    this.accent = const Color(0xFFD8B56A), // small gold details
    this.strap = const Color(0xFFE6DDCF), // interlaced bands
    this.strapEdge = const Color(0xFF06182C), // outline around the bands
  });

  final Color ground, primary, light, accent, strap, strapEdge;

  /// Builds a theme-matched palette from [scheme] (light or dark).
  ///
  /// Light + [bold] (default): a rich tile look in the scheme's primary colour -
  /// deep field, bright medallions, cream bands, gold details. Put content on a
  /// Card/surface so text stays readable.
  /// Light + `bold: false`: a pale, quiet tint of the surface colour.
  /// Dark: muted slate tones that sit behind content.
  ///
  /// Keep `opacity: 1` - blending with transparency is what muddies colours.
  factory PatternColors.fromScheme(ColorScheme scheme, {bool bold = true}) {
    Color mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;
    const white = Color(0xFFFFFFFF);
    const black = Color(0xFF000000);
    const gold = Color(0xFFC9A227);
    final bg = scheme.surface;
    final p = scheme.primary;

    if (scheme.brightness == Brightness.light) {
      if (bold) {
        return PatternColors(
          ground: mix(p, black, 0.32),
          primary: mix(p, white, 0.10),
          light: mix(p, white, 0.55),
          accent: const Color(0xFFE3B94F),
          strap: const Color(0xFFF5EFE2),
          strapEdge: mix(p, black, 0.72),
        );
      }
      return PatternColors(
        ground: mix(bg, p, 0.07),
        primary: mix(bg, p, 0.24),
        light: mix(bg, p, 0.13),
        accent: mix(bg, gold, 0.55),
        strap: bg,
        strapEdge: mix(bg, p, 0.42),
      );
    }
    return PatternColors(
      ground: mix(bg, p, 0.05),
      primary: mix(bg, p, 0.20),
      light: mix(bg, p, 0.34),
      accent: mix(bg, gold, 0.50),
      strap: mix(bg, p, 0.55),
      strapEdge: mix(bg, black, 0.50),
    );
  }

  PatternColors copyWith({Color? ground, Color? primary, Color? light, Color? accent, Color? strap, Color? strapEdge}) => PatternColors(
    ground: ground ?? this.ground,
    primary: primary ?? this.primary,
    light: light ?? this.light,
    accent: accent ?? this.accent,
    strap: strap ?? this.strap,
    strapEdge: strapEdge ?? this.strapEdge,
  );
}

class GeometricPattern extends StatelessWidget {
  const GeometricPattern({
    super.key,
    this.colors = const PatternColors(),
    this.tileSize = 280,
    this.opacity = 1,
    this.offset = Offset.zero,
    this.child,
    required this.assetPath,
  });

  final PatternColors colors;
  final double tileSize;
  final double opacity;
  final Offset offset;
  final Widget? child;

  final String assetPath;

  @override
  Widget build(BuildContext context) {
    return TiledSvg.asset(
      assetPath,
      tileSize: tileSize,
      opacity: opacity,
      offset: offset,
      backgroundColor: colors.ground,
      colorMap: {
        const Color(0xFF0A2540): colors.ground,
        const Color(0xFF1B9FBF): colors.primary,
        const Color(0xFF5FD3DE): colors.light,
        const Color(0xFFD8B56A): colors.accent,
        const Color(0xFFE6DDCF): colors.strap,
        const Color(0xFF06182C): colors.strapEdge,
      },
      child: child,
    );
  }
}
