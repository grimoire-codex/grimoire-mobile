import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/settings.dart';

/// Where someone left off in a book.
class ReadingProgress {
  const ReadingProgress({required this.book, required this.page, required this.updatedAt});

  final Book book;
  final int page;
  final DateTime updatedAt;

  factory ReadingProgress.fromJson(Map<String, dynamic> json) => ReadingProgress(
    book: Book.fromJson(json['book'] as Map<String, dynamic>),
    page: json['page'] as int? ?? 1,
    updatedAt:
        DateTime.tryParse(json['updated_at'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );

  Map<String, dynamic> toJson() => {
    'book': book.toJson(),
    'page': page,
    'updated_at': updatedAt.toIso8601String(),
  };
}

/// Reading positions, kept on the device like the web reader keeps them in
/// the browser. Newest first.
class ProgressController extends Notifier<List<ReadingProgress>> {
  static const _key = 'reading.progress';
  static const _keep = 30;

  @override
  List<ReadingProgress> build() {
    final raw = ref.watch(preferencesProvider).getString(_key);
    if (raw == null) return const [];
    try {
      return [
        for (final e in jsonDecode(raw) as List)
          ReadingProgress.fromJson(e as Map<String, dynamic>),
      ];
    } on FormatException {
      return const [];
    }
  }

  int? pageFor(String bookId) {
    for (final p in state) {
      if (p.book.id == bookId) return p.page;
    }
    return null;
  }

  void save(Book book, int page) {
    final next = [
      ReadingProgress(book: book, page: page, updatedAt: DateTime.now()),
      ...state.where((p) => p.book.id != book.id),
    ].take(_keep).toList();
    state = next;
    ref.read(preferencesProvider).setString(_key, jsonEncode([for (final p in next) p.toJson()]));
  }

  void forget(String bookId) {
    state = state.where((p) => p.book.id != bookId).toList();
    ref.read(preferencesProvider).setString(_key, jsonEncode([for (final p in state) p.toJson()]));
  }
}

final progressProvider = NotifierProvider<ProgressController, List<ReadingProgress>>(
  ProgressController.new,
);
