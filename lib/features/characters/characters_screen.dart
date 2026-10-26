import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/auth.dart';
import '../../core/disk_cache.dart';
import '../../core/models.dart';
import '../../core/reachability.dart';
import '../../widgets/offline_banner.dart';
import '../reader/page_images.dart';

final charactersProvider = FutureProvider.autoDispose<List<Character>>((ref) async {
  final api = ref.watch(apiProvider);
  if (api == null) return const [];
  return api.characters();
});

class CharactersScreen extends ConsumerWidget {
  const CharactersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reachable = ref.watch(reachabilityProvider);
    final characters = ref.watch(charactersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Characters')),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: !reachable
                ? const _Message(
                    'Character sheets open from your Grimoire server. '
                    'Reconnect to see them.',
                  )
                : RefreshIndicator(
                    onRefresh: () => ref.refresh(charactersProvider.future),
                    child: characters.when(
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (e, _) => _Message(describeError(e)),
                      data: (list) => list.isEmpty
                          ? const _Message(
                              'No characters yet. Create one in Grimoire '
                              'and it will appear here.',
                            )
                          : _CharacterList(characters: list),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _CharacterList extends StatelessWidget {
  const _CharacterList({required this.characters});

  final List<Character> characters;

  @override
  Widget build(BuildContext context) {
    final mine = characters.where((c) => c.owned).toList();
    final party = characters.where((c) => !c.owned).toList();
    return ListView(
      children: [
        if (mine.isNotEmpty) ...[
          const _Header('Yours'),
          for (final c in mine) _CharacterTile(character: c),
        ],
        if (party.isNotEmpty) ...[
          const _Header('Your parties'),
          for (final c in party) _CharacterTile(character: c),
        ],
      ],
    );
  }
}

class _CharacterTile extends ConsumerWidget {
  const _CharacterTile({required this.character});

  final Character character;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(apiProvider);
    final theme = Theme.of(context);
    final details = [
      ?character.schemaName ?? character.system,
      ?character.campaignName,
      if (!character.owned && character.ownerName != null) character.ownerName!,
    ];
    final initial = character.name.isEmpty ? '?' : character.name.characters.first.toUpperCase();

    return ListTile(
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        foregroundImage: api != null && character.hasPortrait
            ? ServerImage(
                cache: ref.watch(imageCacheProvider),
                cacheKey: 'portrait-${character.id}-${character.portraitVersion ?? 0}.img',
                fetch: () =>
                    api.characterPortrait(character.id, version: character.portraitVersion),
              )
            : null,
        child: Text(initial),
      ),
      title: Text(character.name.isEmpty ? 'Unnamed' : character.name),
      subtitle: Text(details.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: character.status == 'active'
          ? const Icon(Icons.chevron_right)
          : Chip(
              label: Text(character.status == 'dead' ? 'Dead' : 'Retired'),
              visualDensity: VisualDensity.compact,
            ),
      onTap: () => context.push('/character/${character.id}', extra: character),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => ListView(
    // A list, so pull-to-refresh still works on an empty or error state.
    children: [
      Padding(
        padding: const EdgeInsets.all(32),
        child: Text(text, textAlign: TextAlign.center),
      ),
    ],
  );
}
