import 'package:flutter/material.dart';

import 'inline_spinner.dart';

/// The last row of a paged list: a spinner while the next page loads, a retry button after a failure,
/// otherwise the "Load more" button.
class ListFooter extends StatelessWidget {
  const ListFooter({
    super.key,
    required this.isLoading,
    required this.hasError,
    required this.onLoadMore,
    required this.onRetry,
    this.loadMoreLabel = 'Load more',
    this.errorLabel = "Couldn't load more",
    this.retryLabel = 'Retry',
  });

  final bool isLoading;
  final bool hasError;
  final VoidCallback onLoadMore;
  final VoidCallback onRetry;
  final String loadMoreLabel;
  final String errorLabel;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (isLoading) {
      content = const InlineSpinner();
    } else if (hasError) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(errorLabel),
          TextButton(onPressed: onRetry, child: Text(retryLabel)),
        ],
      );
    } else {
      content = OutlinedButton(onPressed: onLoadMore, child: Text(loadMoreLabel));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(child: content),
    );
  }
}
