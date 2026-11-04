import 'package:flutter/material.dart';

/// The last row of a results list: a spinner while the next page loads, a retry button after a failure,
/// or the "Load more" button of [LoadMoreMode.loadMoreButton].
class ResultsListFooter extends StatelessWidget {
  const ResultsListFooter({
    super.key,
    required this.isLoadingNextPage,
    required this.hasLoadingError,
    required this.onLoadMorePressed,
    required this.onRetryPressed,
  });

  final bool isLoadingNextPage;
  final bool hasLoadingError;
  final VoidCallback onLoadMorePressed;
  final VoidCallback onRetryPressed;

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (isLoadingNextPage) {
      content = const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2));
    } else if (hasLoadingError) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("Couldn't load more"),
          TextButton(onPressed: onRetryPressed, child: const Text('Retry')),
        ],
      );
    } else {
      content = OutlinedButton(onPressed: onLoadMorePressed, child: const Text('Load more'));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(child: content),
    );
  }
}
