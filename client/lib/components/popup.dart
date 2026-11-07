import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

class Popup extends StatelessWidget {
  const Popup({super.key, required this.child, this.onClose, this.leadings, this.constraints});

  final Widget child;
  final List<Widget>? leadings;
  final Function()? onClose;
  final BoxConstraints? constraints;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final container = Container(
      margin: EdgeInsetsGeometry.all(24.0),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Material(
          elevation: 5,
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(spacing: 5, crossAxisAlignment: CrossAxisAlignment.center, children: (leadings ?? [])),
                    ),
                    IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: onClose),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );

    return constraints == null
        ? container
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [ConstrainedBox(constraints: constraints!, child: container)],
          );
  }
}
