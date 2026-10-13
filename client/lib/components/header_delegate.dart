import 'dart:math';

import 'package:flutter/material.dart';

class HeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double? height;
  final double? minHeight;
  final double? maxHeight;

  HeaderDelegate({required this.child, this.height, this.minHeight, this.maxHeight});

  @override
  double get minExtent => min(minHeight ?? height ?? 200, maxHeight ?? height ?? 200);

  @override
  double get maxExtent => max(minHeight ?? height ?? 200, maxHeight ?? height ?? 200);

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  bool shouldRebuild(covariant HeaderDelegate oldDelegate) {
    return oldDelegate.child != child || oldDelegate.height != height || oldDelegate.minExtent != minExtent || oldDelegate.maxExtent != maxExtent;
  }
}
