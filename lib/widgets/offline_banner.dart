import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/reachability.dart';

/// A slim strip shown while the server can't be reached.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reachable = ref.watch(reachabilityProvider);
    final scheme = Theme.of(context).colorScheme;
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      child: reachable
          ? const SizedBox(width: double.infinity)
          : Material(
              color: scheme.surfaceContainerHigh,
              child: InkWell(
                onTap: () => ref.read(reachabilityProvider.notifier).check(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.cloud_off, size: 18, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Offline - showing your downloaded books',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ),
                      Text('Retry', style: TextStyle(color: scheme.primary)),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
