import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/reachability.dart';
import '../../core/storage.dart';
import '../../widgets/cover.dart';
import '../downloads/download_manager.dart';
import '../reader/progress.dart';
import 'library_providers.dart';
import 'system_screen.dart';

class BookScreen extends ConsumerWidget {
  const BookScreen({super.key, required this.bookId, this.preview});

  final String bookId;
  final Book? preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(bookProvider(bookId));
    final book = async.value ?? preview;

    return Scaffold(
      appBar: AppBar(),
      body: book == null
          ? Center(
              child: async.hasError
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(describeError(async.error!), textAlign: TextAlign.center),
                    )
                  : const CircularProgressIndicator(),
            )
          : _BookDetails(book: book),
    );
  }
}

class _BookDetails extends ConsumerWidget {
  const _BookDetails({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final page = ref.watch(
      progressProvider.select((list) => list.where((p) => p.book.id == book.id).firstOrNull?.page),
    );
    final facts = [
      if (book.pageCount != null) '${book.pageCount} pages',
      if (book.year != null) '${book.year}',
      if (book.publisher != null && book.publisher!.isNotEmpty) book.publisher!,
      if (book.fileSize != null) formatBytes(book.fileSize!),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      children: [
        Center(
          child: SizedBox(
            width: 180,
            child: AspectRatio(
              aspectRatio: 0.72,
              child: Hero(
                tag: 'cover-${book.id}',
                child: BookCover(book: book, radius: 12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(book.title, textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
        if (book.systemName != null) ...[
          const SizedBox(height: 4),
          Text(
            '${book.systemName} · ${categoryLabel(book.category)}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
        if (book.authors.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            book.authors.join(', '),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 20),
        if (book.hasPages)
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            icon: const Icon(Icons.menu_book),
            label: Text(page == null ? 'Read' : 'Continue from page $page'),
            onPressed: () => context.push('/read/${book.id}'),
          )
        else
          const Text(
            'Text documents can\'t be opened in the app yet.',
            textAlign: TextAlign.center,
          ),
        const SizedBox(height: 12),
        _DownloadButton(book: book),
        if (facts.isNotEmpty) ...[
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final f in facts) Chip(label: Text(f), visualDensity: VisualDensity.compact),
            ],
          ),
        ],
        if (book.description != null && book.description!.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(book.description!, style: theme.textTheme.bodyMedium),
        ],
        if (book.tags.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in book.tags) Chip(label: Text(t), visualDensity: VisualDensity.compact),
            ],
          ),
        ],
      ],
    );
  }
}

class _DownloadButton extends ConsumerWidget {
  const _DownloadButton({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(downloadsProvider.select((d) => d[book.id]));
    final manager = ref.read(downloadsProvider.notifier);
    final reachable = ref.watch(reachabilityProvider);
    const size = Size.fromHeight(48);

    if (!book.isPdf) {
      return const Text(
        'Only PDFs can be downloaded for offline reading.',
        textAlign: TextAlign.center,
      );
    }
    if (entry == null || entry.status == DownloadStatus.failed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: size),
            icon: const Icon(Icons.download),
            label: Text(entry == null ? 'Download for offline' : 'Retry download'),
            onPressed: reachable ? () => manager.download(book) : null,
          ),
          if (entry?.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(entry!.error!, textAlign: TextAlign.center),
            ),
        ],
      );
    }
    if (entry.isActive) {
      final pct = entry.progress;
      return OutlinedButton(
        style: OutlinedButton.styleFrom(minimumSize: size),
        onPressed: () => manager.cancel(book.id),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2, value: pct),
            ),
            const SizedBox(width: 12),
            Text(
              pct == null
                  ? 'Downloading… tap to cancel'
                  : 'Downloading ${(pct * 100).round()}% · cancel',
            ),
          ],
        ),
      );
    }
    final stale =
        book.contentToken != null &&
        entry.book.contentToken != null &&
        book.contentToken != entry.book.contentToken;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.offline_pin, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text('Downloaded · ${formatBytes(entry.total)}')),
            TextButton(onPressed: () => manager.delete(book.id), child: const Text('Remove')),
          ],
        ),
        if (stale && reachable)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: size),
            icon: const Icon(Icons.sync),
            label: const Text('The file changed on the server - update download'),
            onPressed: () => manager.download(book),
          ),
      ],
    );
  }
}
