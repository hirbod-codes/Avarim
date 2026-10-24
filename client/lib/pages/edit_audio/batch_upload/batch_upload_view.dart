// batch_upload_view.dart
//
// What EditAudioPage shows during / after a batch upload (see batch_upload_notifier.dart):
//   running           -> progress + the list of files
//   failed / cancelled-> the last successful audio and the one that failed, then the full list
//   done              -> the list of files, each with an Edit button

import 'dart:async';

import 'package:avarim/pages/edit_audio/batch_upload/batch_upload_notifier.dart';
import 'package:avarim/pages/edit_audio/edit_audio_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BatchUploadView extends ConsumerWidget {
  const BatchUploadView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(batchUploadProvider);
    final notifier = ref.read(batchUploadProvider.notifier);
    final theme = Theme.of(context);

    final total = s.items.length;
    final doneCount = s.doneCount;
    final stopped = s.phase == BatchPhase.failed || s.phase == BatchPhase.cancelled;
    final notUploaded = s.items.where((i) => i.status == BatchItemStatus.skipped || i.status == BatchItemStatus.cancelled).length;

    // Opens that audio in the editor (the page then offers "Back to uploads").
    void edit(String id) => unawaited(ref.read(audioUploadProvider.notifier).openExisting(id));

    final tiles = [for (final it in s.items) _ItemTile(item: it, onEdit: it.status == BatchItemStatus.done && it.id != null ? () => edit(it.id!) : null)];

    final title = switch (s.phase) {
      BatchPhase.running => 'Uploading audio ${doneCount + 1} of $total',
      BatchPhase.failed => 'Upload stopped',
      BatchPhase.cancelled => 'Upload cancelled',
      BatchPhase.done => 'All $total audios uploaded',
      BatchPhase.idle => '',
    };

    final last = s.lastSucceeded;
    final failed = s.failedItem;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          s.phase == BatchPhase.running
              ? 'Each audio is uploaded after the previous one has finished processing. Keep this page open.'
              : '$doneCount of $total uploaded.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        LinearProgressIndicator(value: total == 0 ? 0 : doneCount / total),
        const SizedBox(height: 16),

        if (stopped) ...[
          Card(
            child: ListTile(
              leading: Icon(Icons.check_circle_outline, color: last == null ? theme.colorScheme.outline : Colors.green),
              title: Text(last?.audio.name ?? 'No audio was uploaded successfully'),
              subtitle: Text(last == null ? 'Last successful upload' : 'Last successful upload · ${last.id}'),
              trailing: last?.id == null ? null : TextButton(onPressed: () => edit(last!.id!), child: const Text('Edit')),
            ),
          ),
          if (failed != null)
            Card(
              color: theme.colorScheme.errorContainer,
              child: ListTile(
                leading: Icon(Icons.error_outline, color: theme.colorScheme.error),
                title: Text(failed.audio.name),
                subtitle: Text('Failed: ${failed.error ?? 'Unknown error'}'),
                isThreeLine: true,
              ),
            ),
          if (notUploaded > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('$notUploaded more ${notUploaded == 1 ? 'file was' : 'files were'} not uploaded.', style: theme.textTheme.bodySmall),
            ),
          ExpansionTile(title: Text('All files ($total)'), children: tiles),
        ] else
          ...tiles,

        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (s.phase == BatchPhase.running) OutlinedButton(onPressed: notifier.cancel, child: const Text('Cancel')),
            if (stopped) FilledButton(onPressed: notifier.retry, child: Text(s.phase == BatchPhase.failed ? 'Retry' : 'Resume')),
            if (s.phase != BatchPhase.running)
              OutlinedButton(onPressed: notifier.reset, child: Text(s.phase == BatchPhase.done ? 'Upload more' : 'Start over')),
          ],
        ),
      ],
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, this.onEdit});

  final BatchItem item;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (icon, color) = switch (item.status) {
      BatchItemStatus.pending => (Icons.schedule, theme.colorScheme.outline),
      BatchItemStatus.uploading => (Icons.cloud_upload_outlined, theme.colorScheme.primary),
      BatchItemStatus.processing => (Icons.hourglass_top, theme.colorScheme.primary),
      BatchItemStatus.done => (Icons.check_circle_outline, Colors.green),
      BatchItemStatus.failed => (Icons.error_outline, theme.colorScheme.error),
      BatchItemStatus.cancelled || BatchItemStatus.skipped => (Icons.block, theme.colorScheme.outline),
    };

    final Widget? subtitle = switch (item.status) {
      BatchItemStatus.pending => const Text('Waiting'),
      BatchItemStatus.uploading => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Uploading… ${(item.progress * 100).round()}%'),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: item.progress),
        ],
      ),
      BatchItemStatus.processing => const Text('Processing on the server…'),
      BatchItemStatus.done => null,
      BatchItemStatus.failed => Text(item.error ?? 'Failed'),
      BatchItemStatus.cancelled => Text(item.id == null ? 'Cancelled' : 'Cancelled (the server may still finish processing it)'),
      BatchItemStatus.skipped => const Text('Not uploaded'),
    };

    return ListTile(
      dense: true,
      leading: Icon(icon, color: color),
      title: Text(item.audio.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle,
      trailing: onEdit == null ? null : TextButton(onPressed: onEdit, child: const Text('Edit')),
    );
  }
}
