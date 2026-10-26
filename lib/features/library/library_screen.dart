import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/auth.dart';
import '../../core/models.dart';
import '../../core/reachability.dart';
import '../../widgets/book_tile.dart';
import '../../widgets/cover.dart';
import '../../widgets/offline_banner.dart';
import '../downloads/download_manager.dart';
import '../reader/progress.dart';
import 'library_providers.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reachable = ref.watch(reachabilityProvider);
    final server = ref.watch(authProvider.select((s) => s?.baseUrl)) ?? '';
    final progress = ref.watch(progressProvider);
    final downloads = ref.watch(serverDownloadsProvider).where((d) => d.isDone).toList();

    // Offline, only downloaded books can be opened.
    final continueReading = reachable
        ? progress
        : progress.where((p) => downloads.any((d) => d.book.id == p.book.id)).toList();

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(reachabilityProvider.notifier).check();
          ref.invalidate(systemsProvider);
          ref.invalidate(recentlyAddedProvider);
        },
        child: CustomScrollView(
          slivers: [
            SliverAppBar.medium(
              title: const Text('Library'),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Text(
                    Uri.tryParse(server)?.host ?? '',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
            ),
            const SliverToBoxAdapter(child: OfflineBanner()),
            if (continueReading.isNotEmpty)
              SliverToBoxAdapter(
                child: Shelf(
                  title: 'Continue reading',
                  children: [
                    for (final p in continueReading.take(12))
                      BookTile(
                        book: p.book,
                        subtitle: 'Page ${p.page}',
                        progress: (p.book.pageCount ?? 0) > 0 ? p.page / p.book.pageCount! : null,
                      ),
                  ],
                ),
              ),
            if (reachable) ...[
              const SliverToBoxAdapter(child: _RecentlyAdded()),
              const _SystemsSection(),
            ] else
              ..._downloadedSection(context, downloads),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  List<Widget> _downloadedSection(BuildContext context, List<DownloadEntry> downloads) => [
    SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
        child: Text('Downloaded', style: Theme.of(context).textTheme.titleMedium),
      ),
    ),
    if (downloads.isEmpty)
      const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Nothing downloaded yet. Open a book while online and tap Download to read it offline.',
            textAlign: TextAlign.center,
          ),
        ),
      )
    else
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: bookGrid([for (final d in downloads) d.book], subtitle: (b) => b.systemName),
      ),
  ];
}

class _RecentlyAdded extends ConsumerWidget {
  const _RecentlyAdded();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(recentlyAddedProvider).value ?? const <Book>[];
    if (books.isEmpty) return const SizedBox.shrink();
    return Shelf(
      title: 'Recently added',
      children: [for (final b in books) BookTile(book: b)],
    );
  }
}

class _SystemsSection extends ConsumerWidget {
  const _SystemsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final systems = ref.watch(systemsProvider);
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
            child: Text('Game systems', style: Theme.of(context).textTheme.titleMedium),
          ),
        ),
        systems.when(
          loading: () => const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (e, _) => SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Text(describeError(e), textAlign: TextAlign.center),
                  TextButton(
                    onPressed: () => ref.invalidate(systemsProvider),
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ),
          data: (list) => SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: systemGrid(list),
          ),
        ),
      ],
    );
  }
}

SliverGrid systemGrid(List<GameSystem> systems) => SliverGrid(
  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: 200,
    mainAxisSpacing: 16,
    crossAxisSpacing: 12,
    childAspectRatio: 0.62,
  ),
  delegate: SliverChildBuilderDelegate(
    (context, i) => SystemTile(system: systems[i]),
    childCount: systems.length,
  ),
);

class SystemTile extends StatelessWidget {
  const SystemTile({super.key, required this.system});

  final GameSystem system;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = system.isContainer
        ? '${system.childCount} systems'
        : '${system.bookCount} book${system.bookCount == 1 ? '' : 's'}';
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.push('/library/system/${system.id}', extra: system),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: SystemCover(system: system)),
          const SizedBox(height: 6),
          Text(
            system.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          Text(
            count,
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
