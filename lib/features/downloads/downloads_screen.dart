import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/storage.dart';
import '../../widgets/cover.dart';
import 'download_manager.dart';

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(serverDownloadsProvider);
    final used = entries.where((e) => e.isDone).fold<int>(0, (sum, e) => sum + e.total);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        actions: [
          if (used > 0)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(child: Text(formatBytes(used))),
            ),
        ],
      ),
      body: entries.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Books you download are read on this device, even without a connection.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
              itemBuilder: (context, i) => _DownloadRow(entry: entries[i]),
            ),
    );
  }
}

class _DownloadRow extends ConsumerWidget {
  const _DownloadRow({required this.entry});

  final DownloadEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.read(downloadsProvider.notifier);
    final book = entry.book;
    final Widget subtitle = switch (entry.status) {
      DownloadStatus.done => Text(formatBytes(entry.total)),
      DownloadStatus.failed => Text(entry.error ?? 'Failed'),
      _ => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: LinearProgressIndicator(value: entry.progress),
      ),
    };

    return Dismissible(
      key: ValueKey(book.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Theme.of(context).colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete_outline),
      ),
      onDismissed: (_) => manager.delete(book.id),
      child: ListTile(
        leading: SizedBox(width: 40, height: 56, child: BookCover(book: book, radius: 4)),
        title: Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: subtitle,
        trailing: switch (entry.status) {
          DownloadStatus.done => const Icon(Icons.chevron_right),
          DownloadStatus.failed => IconButton(
            tooltip: 'Retry',
            icon: const Icon(Icons.refresh),
            onPressed: () => manager.download(book),
          ),
          _ => IconButton(
            tooltip: 'Cancel',
            icon: const Icon(Icons.close),
            onPressed: () => manager.cancel(book.id),
          ),
        },
        onTap: entry.isDone ? () => context.push('/book/${book.id}', extra: book) : null,
      ),
    );
  }
}
