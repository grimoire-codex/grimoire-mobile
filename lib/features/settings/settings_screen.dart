import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth.dart';
import '../../core/disk_cache.dart';
import '../../core/settings.dart';
import '../../core/storage.dart';
import '../downloads/download_manager.dart';

final _pageCacheSizeProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(pageCacheProvider).size(),
);

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final server = ref.read(authProvider)?.baseUrl;
    final hasDownloads = ref.read(serverDownloadsProvider).isNotEmpty;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: Text(
          hasDownloads
              ? 'Your downloaded books can stay on this phone for next time, or be removed.'
              : 'You can sign back in at any time.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          if (hasDownloads)
            TextButton(
              onPressed: () => Navigator.pop(context, 'remove'),
              child: const Text('Remove downloads'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'keep'),
            child: Text(hasDownloads ? 'Keep downloads' : 'Sign out'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    if (choice == 'remove') {
      await ref.read(downloadsProvider.notifier).deleteAll(serverUrl: server);
    }
    await ref.read(authProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authProvider);
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    final cacheSize = ref.watch(_pageCacheSizeProvider);
    final downloaded = ref
        .watch(serverDownloadsProvider)
        .where((e) => e.isDone)
        .fold<int>(0, (sum, e) => sum + e.total);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(session?.user?.name ?? ''),
            subtitle: Text(
              '${session?.user?.role ?? ''} · ${Uri.tryParse(session?.baseUrl ?? '')?.host ?? ''}'
              '${session?.usesApiKey == true ? ' · API key' : ''}',
            ),
          ),
          const Divider(),
          const _Header('Reading'),
          SwitchListTile(
            title: const Text('Render downloads on this device'),
            subtitle: const Text(
              'Read downloaded books from the phone even when Grimoire is reachable. '
              'When off, Grimoire renders pages and the download is used offline.',
            ),
            value: settings.preferDeviceRendering,
            onChanged: controller.setPreferDeviceRendering,
          ),
          SwitchListTile(
            title: const Text('Swipe up and down'),
            subtitle: const Text('Turn pages vertically instead of sideways.'),
            value: settings.verticalPaging,
            onChanged: controller.setVerticalPaging,
          ),
          ListTile(
            title: const Text('Page sharpness'),
            subtitle: const Text('Higher is crisper when zoomed but uses more data.'),
            trailing: SegmentedButton<PageQuality>(
              segments: const [
                ButtonSegment(value: PageQuality.standard, label: Text('Standard')),
                ButtonSegment(value: PageQuality.high, label: Text('High')),
              ],
              selected: {settings.quality},
              showSelectedIcon: false,
              onSelectionChanged: (s) => controller.setQuality(s.first),
            ),
          ),
          const Divider(),
          const _Header('Storage'),
          ListTile(title: const Text('Downloaded books'), trailing: Text(formatBytes(downloaded))),
          ListTile(
            title: const Text('Page cache'),
            subtitle: const Text('Pages Grimoire has rendered, kept so they open instantly.'),
            trailing: TextButton(
              onPressed: () async {
                await ref.read(pageCacheProvider).clear();
                await ref.read(imageCacheProvider).clear();
                PaintingBinding.instance.imageCache.clear();
                ref.invalidate(_pageCacheSizeProvider);
              },
              child: Text('Clear ${formatBytes(cacheSize.value ?? 0)}'),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            onTap: () => _signOut(context, ref),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}
