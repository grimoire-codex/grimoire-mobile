import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/auth.dart';
import '../../core/models.dart';
import '../../core/reachability.dart';
import '../../widgets/cover.dart';
import '../downloads/download_manager.dart';

/// Renders a server snippet: HTML-escaped text with `<mark>` around matches.
List<TextSpan> snippetSpans(String snippet, TextStyle highlight) {
  String unescape(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#x27;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&');
  final spans = <TextSpan>[];
  final pattern = RegExp(r'<mark>(.*?)</mark>', dotAll: true);
  var last = 0;
  for (final m in pattern.allMatches(snippet)) {
    if (m.start > last) spans.add(TextSpan(text: unescape(snippet.substring(last, m.start))));
    spans.add(TextSpan(text: unescape(m.group(1)!), style: highlight));
    last = m.end;
  }
  if (last < snippet.length) spans.add(TextSpan(text: unescape(snippet.substring(last))));
  return spans;
}

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  Future<SearchResults>? _results;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(text));
  }

  void _run(String text) {
    final q = text.trim();
    final api = ref.read(apiProvider);
    setState(() {
      _results = q.length < 2 || api == null ? null : api.search(q);
    });
  }

  @override
  Widget build(BuildContext context) {
    final reachable = ref.watch(reachabilityProvider);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _query,
          autofocus: false,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: reachable ? 'Search books and pages' : 'Search downloaded books',
            prefixIcon: const Icon(Icons.search),
            isDense: true,
          ),
          onChanged: _onChanged,
          onSubmitted: _run,
        ),
      ),
      body: reachable ? _serverResults(context) : _offlineResults(context),
    );
  }

  Widget _serverResults(BuildContext context) {
    if (_results == null) {
      return const _Hint(text: 'Search titles, authors and the full text of indexed books.');
    }
    return FutureBuilder<SearchResults>(
      future: _results,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return _Hint(text: describeError(snapshot.error!));
        final results = snapshot.data!;
        if (results.isEmpty) return const _Hint(text: 'No matches.');
        final theme = Theme.of(context);
        final highlight = TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w700);
        return ListView(
          children: [
            if (results.books.isNotEmpty) ...[
              const _SectionTitle('Books'),
              for (final b in results.books) _BookRow(book: b),
            ],
            if (results.pages.isNotEmpty) ...[
              const _SectionTitle('Pages'),
              for (final hit in results.pages)
                ListTile(
                  title: Text(hit.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text.rich(
                    TextSpan(children: snippetSpans(hit.snippet, highlight)),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text('p. ${hit.page}'),
                  onTap: () => context.push('/read/${hit.bookId}?page=${hit.page}'),
                ),
            ],
          ],
        );
      },
    );
  }

  Widget _offlineResults(BuildContext context) {
    final q = _query.text.trim().toLowerCase();
    final books = ref
        .watch(serverDownloadsProvider)
        .where((d) => d.isDone)
        .map((d) => d.book)
        .where((b) => q.isEmpty || b.title.toLowerCase().contains(q))
        .toList();
    if (books.isEmpty) return const _Hint(text: 'No downloaded books match.');
    return ListView(children: [for (final b in books) _BookRow(book: b)]);
  }
}

class _BookRow extends StatelessWidget {
  const _BookRow({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: SizedBox(width: 40, height: 56, child: BookCover(book: book, radius: 4)),
      title: Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: book.systemName == null ? null : Text(book.systemName!),
      onTap: () => context.push('/book/${book.id}', extra: book),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );
}
