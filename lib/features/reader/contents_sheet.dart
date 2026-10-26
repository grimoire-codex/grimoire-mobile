import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/auth.dart';
import '../../core/models.dart';
import 'reader_controller.dart';

Future<void> showContentsSheet(
  BuildContext context, {
  required ReaderState state,
  required int currentPage,
  required ValueChanged<int> onSelect,
  required bool showBookmarks,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.7,
    maxChildSize: 0.95,
    builder: (context, scroll) => _ContentsSheet(
      state: state,
      currentPage: currentPage,
      scroll: scroll,
      showBookmarks: showBookmarks,
      onSelect: (page) {
        Navigator.pop(context);
        onSelect(page);
      },
    ),
  ),
);

class _ContentsSheet extends StatelessWidget {
  const _ContentsSheet({
    required this.state,
    required this.currentPage,
    required this.scroll,
    required this.showBookmarks,
    required this.onSelect,
  });

  final ReaderState state;
  final int currentPage;
  final ScrollController scroll;
  final bool showBookmarks;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final toc = _TocList(state: state, scroll: scroll, onSelect: onSelect);
    if (!showBookmarks) return toc;
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Contents'),
              Tab(text: 'Bookmarks'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                toc,
                _BookmarkList(bookId: state.book.id, currentPage: currentPage, onSelect: onSelect),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TocList extends StatelessWidget {
  const _TocList({required this.state, required this.scroll, required this.onSelect});

  final ReaderState state;
  final ScrollController scroll;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TocEntry>>(
      future: state.source.toc(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final entries = TocEntry.flatten(snapshot.data ?? const [])
            .where((e) => e.page > 0)
            .toList();
        if (entries.isEmpty) {
          return const Center(child: Text('This book has no table of contents.'));
        }
        return ListView.builder(
          controller: scroll,
          itemCount: entries.length,
          itemBuilder: (context, i) {
            final e = entries[i];
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.only(left: 16.0 * e.level, right: 16),
              title: Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: Text('${e.page}'),
              onTap: () => onSelect(e.page),
            );
          },
        );
      },
    );
  }
}

class _BookmarkList extends ConsumerWidget {
  const _BookmarkList({required this.bookId, required this.currentPage, required this.onSelect});

  final String bookId;
  final int currentPage;
  final ValueChanged<int> onSelect;

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(apiProvider)?.addBookmark(bookId, currentPage);
      ref.invalidate(bookmarksProvider(bookId));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarks = ref.watch(bookmarksProvider(bookId));
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.bookmark_add_outlined),
          title: Text('Bookmark page $currentPage'),
          onTap: () => _add(context, ref),
        ),
        const Divider(height: 1),
        Expanded(
          child: bookmarks.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text(describeError(e))),
            data: (list) => list.isEmpty
                ? const Center(child: Text('No bookmarks yet.'))
                : ListView(
                    children: [
                      for (final b in list)
                        Dismissible(
                          key: ValueKey(b.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            color: Theme.of(context).colorScheme.errorContainer,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 24),
                            child: const Icon(Icons.delete_outline),
                          ),
                          onDismissed: (_) async {
                            await ref.read(apiProvider)?.deleteBookmark(b.id);
                            ref.invalidate(bookmarksProvider(bookId));
                          },
                          child: ListTile(
                            leading: const Icon(Icons.bookmark_outline),
                            title: Text(
                              (b.label?.isNotEmpty ?? false) ? b.label! : 'Page ${b.page}',
                            ),
                            trailing: Text('${b.page}'),
                            onTap: () => onSelect(b.page),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
