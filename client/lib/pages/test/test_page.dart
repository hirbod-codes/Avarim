import 'package:avarim/pages/test/geometric_pattern.dart';
import 'package:avarim/pages/test/pattern_edge_fade.dart';
import 'package:flutter/material.dart';

class TestPage extends StatelessWidget {
  const TestPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final child = const Text('Your App Content Here', style: TextStyle(color: Colors.white, fontSize: 24));

    // Define the size of each pattern tile. You can adjust this to scale the pattern up or down.
    return Scaffold(
      body:
          // FabricTexture(
          //   threadOpacity: 0.06,
          //   child: GeometricPattern(
          //     assetPath: 'assets/patterns/geometric_pattern_fabric.svg',
          //     colors: PatternColors.fromScheme(theme.colorScheme),
          //     tileSize: 300,
          //     child: child,
          //   ),
          // ),
          PatternEdgeFade(
            assetPath: 'assets/patterns/geometric_pattern2.svg',
            colors: PatternColors.fromScheme(theme.colorScheme),
            tileSize: 150,
            edgeFade: 70,
            hold: 10,
            edgeCurve: Curves.easeIn,
            fadeCurve: Curves.easeOutBack,
            fadeExtent: 100,
            maxOpacity: 0.8,
            // curve: Curves.bounceInOut,
            child: Center(child: child),
          ),
    )
    //   GeometricPattern(
    //     assetPath: 'assets/patterns/geometric_pattern2.svg',
    //     // colors: const PatternColors(ground: Color(0xFF101828), primary: Color(0xFF7C3AED)),
    //     colors: PatternColors(ground: theme.colorScheme.surface, primary: theme.colorScheme.primary),
    //     tileSize: 260,
    //     // opacity: 0.35,
    //     child: SafeArea(
    //       child: child,
    //     ),
    //   ),
    // )
    ;

    // const double tileSize = 120.0;
    // return Scaffold(
    //   // backgroundColor: const Color(0xFF061A2B), // Matches the SVG navy background to prevent gaps
    //   body: Stack(
    //     children: [
    //       // Tiling Background Layer
    //       Positioned.fill(
    //         child: ClipRect(
    //           child: LayoutBuilder(
    //             builder: (context, constraints) {
    //               // Calculate how many tiles we need to fill the screen
    //               final int columns = (constraints.maxWidth / tileSize).ceil();
    //               final int rows = (constraints.maxHeight / tileSize).ceil();
    //               final int totalTiles = columns * rows;

    //               return Wrap(
    //                 children: List.generate(totalTiles, (index) {
    //                   return SvgPicture.asset('assets/background.svg', width: tileSize, height: tileSize);
    //                 }),
    //               );
    //             },
    //           ),
    //         ),
    //       ),

    //       // Foreground App Content
    //       SafeArea(
    //         child: Center(
    //           child: Container(
    //             padding: const EdgeInsets.all(16),
    //             decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(8)),
    //             child: const Text('Your App Content Here', style: TextStyle(color: Colors.white, fontSize: 24)),
    //           ),
    //         ),
    //       ),
    //     ],
    //   ),
    // );
  }
}
