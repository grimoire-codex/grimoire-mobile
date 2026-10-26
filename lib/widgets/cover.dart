import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth.dart';
import '../core/disk_cache.dart';
import '../core/models.dart';
import '../features/downloads/download_manager.dart';
import '../features/reader/page_images.dart';

/// A book's cover: the downloaded copy's saved cover when there is one (so
/// the offline library has art), otherwise the server's thumbnail.
class BookCover extends ConsumerWidget {
  const BookCover({super.key, required this.book, this.radius = 8});

  final Book book;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloaded = ref.watch(downloadsProvider.select((d) => d[book.id]?.isDone ?? false));
    final api = ref.watch(apiProvider);
    ImageProvider? image;
    if (downloaded) {
      final file = ref.read(downloadsProvider.notifier).coverFor(book.id);
      if (file.existsSync()) image = FileImage(File(file.path));
    }
    if (image == null && api != null && book.hasThumbnail) {
      image = ServerImage.bookCover(api, ref.watch(imageCacheProvider), book.id);
    }
    return _Art(image: image, title: book.title, radius: radius);
  }
}

class SystemCover extends ConsumerWidget {
  const SystemCover({super.key, required this.system, this.radius = 10});

  final GameSystem system;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(apiProvider);
    final cache = ref.watch(imageCacheProvider);
    ImageProvider? image;
    if (api != null) {
      if (system.hasCover) {
        image = ServerImage.systemCover(api, cache, system.id);
      } else if (system.coverBookId != null) {
        image = ServerImage.bookCover(api, cache, system.coverBookId!);
      }
    }
    return _Art(image: image, title: system.name, radius: radius);
  }
}

class _Art extends StatelessWidget {
  const _Art({required this.image, required this.title, required this.radius});

  final ImageProvider? image;
  final String title;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final fallback = _Placeholder(title: title);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: image == null
          ? fallback
          : Image(
              image: image!,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              frameBuilder: (context, child, frame, wasSync) =>
                  frame == null && !wasSync ? fallback : child,
              errorBuilder: (context, error, stack) => fallback,
            ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.surfaceContainerHigh, scheme.surfaceContainer],
        ),
      ),
      padding: const EdgeInsets.all(10),
      alignment: Alignment.center,
      child: Text(
        title,
        textAlign: TextAlign.center,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}
