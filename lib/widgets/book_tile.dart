import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/models.dart';
import '../features/downloads/download_manager.dart';
import 'cover.dart';

/// Cover-first tile used in every book grid and shelf.
class BookTile extends ConsumerWidget {
  const BookTile({super.key, required this.book, this.progress, this.subtitle});

  final Book book;

  /// 0-1 reading progress, drawn as a thin bar under the cover.
  final double? progress;
  final String? subtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloaded = ref.watch(downloadsProvider.select((d) => d[book.id]?.isDone ?? false));
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => context.push('/book/${book.id}', extra: book),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 0.72,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Hero(
                  tag: 'cover-${book.id}',
                  child: BookCover(book: book),
                ),
                if (downloaded)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: CircleAvatar(
                      radius: 11,
                      backgroundColor: Colors.black.withValues(alpha: 0.65),
                      child: Icon(Icons.offline_pin, size: 16, color: theme.colorScheme.primary),
                    ),
                  ),
                if (progress != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 3,
                      backgroundColor: Colors.black54,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            book.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// A grid of book tiles sized for the screen: ~3 across on a phone, more on
/// a tablet.
SliverGrid bookGrid(List<Book> books, {String? Function(Book)? subtitle}) => SliverGrid(
  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: 140,
    mainAxisSpacing: 16,
    crossAxisSpacing: 12,
    childAspectRatio: 0.5,
  ),
  delegate: SliverChildBuilderDelegate(
    (context, i) => BookTile(book: books[i], subtitle: subtitle?.call(books[i])),
    childCount: books.length,
  ),
);

/// A titled horizontal shelf.
class Shelf extends StatelessWidget {
  const Shelf({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        SizedBox(
          height: 232,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: children.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) => SizedBox(width: 112, child: children[i]),
          ),
        ),
      ],
    );
  }
}
