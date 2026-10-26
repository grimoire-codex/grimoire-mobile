import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../widgets/book_tile.dart';
import 'library_providers.dart';
import 'library_screen.dart';

const _categoryLabels = {
  'core': 'Core rules',
  'supplement': 'Supplements',
  'adventure': 'Adventures',
  'character-sheet': 'Character sheets',
  'map': 'Maps',
  'handout': 'Handouts',
  'homebrew': 'Homebrew',
  'starter-set': 'Starter sets',
  'magazine': 'Magazines',
};

String categoryLabel(String? category) {
  if (category == null || category.isEmpty) return 'Other';
  return _categoryLabels[category] ??
      category[0].toUpperCase() + category.substring(1).replaceAll('-', ' ');
}

class SystemScreen extends ConsumerWidget {
  const SystemScreen({super.key, required this.systemId, this.preview});

  final String systemId;

  /// The list row we came from, so the title shows before the detail loads.
  final GameSystem? preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(systemDetailProvider(systemId));
    final title = detail.value?.system.name ?? preview?.name ?? '';

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(systemDetailProvider(systemId).future),
        child: CustomScrollView(
          slivers: [
            SliverAppBar.medium(title: Text(title)),
            ...detail.when(
              loading: () => const [
                SliverFillRemaining(child: Center(child: CircularProgressIndicator())),
              ],
              error: (e, _) => [SliverFillRemaining(child: Center(child: Text(describeError(e))))],
              data: (d) => _content(context, d),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context, SystemDetail detail) {
    final groups = <String, List<Book>>{};
    for (final b in detail.books) {
      groups.putIfAbsent(categoryLabel(b.category), () => []).add(b);
    }
    final description = detail.system.description;
    return [
      if (description != null && description.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              description,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      if (detail.children.isNotEmpty) ...[
        _header(context, 'Systems'),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: systemGrid(detail.children),
        ),
      ],
      for (final entry in groups.entries) ...[
        _header(context, '${entry.key} · ${entry.value.length}'),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: bookGrid(entry.value),
        ),
      ],
      if (detail.books.isEmpty && detail.children.isEmpty)
        const SliverFillRemaining(child: Center(child: Text('No books here yet.'))),
    ];
  }

  Widget _header(BuildContext context, String text) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    ),
  );
}
