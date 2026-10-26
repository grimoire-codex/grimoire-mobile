// Plain data classes for the parts of the Grimoire API the app reads.
//
// Field names follow the server's JSON (see `docs/api.md` in the grimoire repo).
// Each class can round-trip through JSON so downloaded books keep their
// metadata on disk and stay browsable offline.

List<String> _strings(Object? value) =>
    value is List ? value.whereType<String>().toList() : const [];

int? _int(Object? value) => value is num ? value.toInt() : null;

class User {
  const User({required this.id, required this.username, required this.role, this.displayName});

  final String id;
  final String username;
  final String role;
  final String? displayName;

  String get name => (displayName != null && displayName!.isNotEmpty) ? displayName! : username;

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: '${json['id']}',
    username: json['username'] as String? ?? '',
    role: json['role'] as String? ?? 'player',
    displayName: json['display_name'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'role': role,
    'display_name': displayName,
  };
}

class Book {
  const Book({
    required this.id,
    required this.title,
    this.filename = '',
    this.category,
    this.pageCount,
    this.mimeType,
    this.contentToken,
    this.fileSize,
    this.hasThumbnail = false,
    this.systemId,
    this.systemName,
    this.authors = const [],
    this.publisher,
    this.year,
    this.description,
    this.tags = const [],
  });

  final String id;
  final String title;
  final String filename;
  final String? category;
  final int? pageCount;
  final String? mimeType;

  /// Changes whenever the file's contents change. Used to key cached page
  /// images and to spot a downloaded copy that has gone stale.
  final String? contentToken;
  final int? fileSize;
  final bool hasThumbnail;
  final String? systemId;
  final String? systemName;
  final List<String> authors;
  final String? publisher;
  final int? year;
  final String? description;
  final List<String> tags;

  bool get isPdf => mimeType == 'application/pdf' || filename.toLowerCase().endsWith('.pdf');

  /// Text documents have no rendered pages on the server.
  bool get hasPages =>
      mimeType == null || !(mimeType!.startsWith('text/') || mimeType == 'application/rtf');

  factory Book.fromJson(Map<String, dynamic> json) {
    final system = json['game_system'];
    return Book(
      id: '${json['id']}',
      title: json['title'] as String? ?? json['filename'] as String? ?? '',
      filename: json['filename'] as String? ?? '',
      category: json['category'] as String?,
      pageCount: _int(json['page_count']),
      mimeType: json['mime_type'] as String?,
      contentToken: json['content_token'] as String?,
      fileSize: _int(json['file_size']),
      hasThumbnail: json['has_thumbnail'] as bool? ?? false,
      systemId: system is Map
          ? '${system['id']}'
          : (json['game_system_id'] ?? json['system_id']) as String?,
      systemName: system is Map
          ? system['name'] as String?
          : (system is String ? system : json['system_name'] as String?),
      authors: _strings(json['authors']),
      publisher: json['publisher'] as String?,
      year: _int(json['year']),
      description: json['description'] as String?,
      tags: _strings(json['tags']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'filename': filename,
    'category': category,
    'page_count': pageCount,
    'mime_type': mimeType,
    'content_token': contentToken,
    'file_size': fileSize,
    'has_thumbnail': hasThumbnail,
    'system_id': systemId,
    'system_name': systemName,
    'authors': authors,
    'publisher': publisher,
    'year': year,
    'description': description,
    'tags': tags,
  };
}

class GameSystem {
  const GameSystem({
    required this.id,
    required this.name,
    this.bookCount = 0,
    this.childCount = 0,
    this.hasCover = false,
    this.coverBookId,
    this.containerKind = '',
    this.description,
    this.publishers = const [],
    this.year,
  });

  final String id;
  final String name;
  final int bookCount;
  final int childCount;
  final bool hasCover;
  final String? coverBookId;
  final String containerKind;
  final String? description;
  final List<String> publishers;
  final int? year;

  bool get isContainer => containerKind.isNotEmpty;

  factory GameSystem.fromJson(Map<String, dynamic> json) => GameSystem(
    id: '${json['id']}',
    name: json['name'] as String? ?? '',
    bookCount: _int(json['book_count']) ?? 0,
    childCount: _int(json['child_count']) ?? 0,
    hasCover: json['has_cover'] as bool? ?? false,
    coverBookId: json['cover_book_id'] as String?,
    containerKind: json['container_kind'] as String? ?? '',
    description: json['description'] as String?,
    publishers: [
      for (final p in (json['publishers'] as List? ?? const []))
        if (p is Map && p['name'] is String) p['name'] as String,
    ],
    year: _int(json['year']),
  );
}

class SystemDetail {
  const SystemDetail({required this.system, required this.books, required this.children});

  final GameSystem system;
  final List<Book> books;
  final List<GameSystem> children;

  factory SystemDetail.fromJson(Map<String, dynamic> json) {
    final system = GameSystem.fromJson(json);
    return SystemDetail(
      system: system,
      books: [
        for (final b in (json['books'] as List? ?? const []))
          Book.fromJson({
            ...(b as Map<String, dynamic>),
            'game_system': {'id': system.id, 'name': system.name},
          }),
      ],
      children: [
        for (final c in (json['children'] as List? ?? const []))
          GameSystem.fromJson(c as Map<String, dynamic>),
      ],
    );
  }
}

class TocEntry {
  const TocEntry({
    required this.title,
    required this.page,
    this.level = 1,
    this.children = const [],
  });

  final String title;

  /// 1-based, or -1 when the destination could not be resolved.
  final int page;
  final int level;
  final List<TocEntry> children;

  factory TocEntry.fromJson(Map<String, dynamic> json) => TocEntry(
    title: json['title'] as String? ?? '',
    page: _int(json['page']) ?? -1,
    level: _int(json['level']) ?? 1,
    children: [
      for (final c in (json['children'] as List? ?? const []))
        TocEntry.fromJson(c as Map<String, dynamic>),
    ],
  );

  Map<String, dynamic> toJson() => {
    'title': title,
    'page': page,
    'level': level,
    'children': [for (final c in children) c.toJson()],
  };

  /// Depth-first list of every entry, for rendering as a flat list.
  static List<TocEntry> flatten(List<TocEntry> entries) => [
    for (final e in entries) ...[e, ...flatten(e.children)],
  ];
}

class PageHit {
  const PageHit({
    required this.bookId,
    required this.title,
    required this.page,
    required this.snippet,
    this.systemName,
  });

  final String bookId;
  final String title;
  final int page;

  /// HTML-escaped text with matches wrapped in `<mark>` tags.
  final String snippet;
  final String? systemName;

  factory PageHit.fromJson(Map<String, dynamic> json) => PageHit(
    bookId: '${json['id']}',
    title: json['title'] as String? ?? '',
    page: _int(json['page_number']) ?? 1,
    snippet: json['snippet'] as String? ?? '',
    systemName: json['game_system'] as String?,
  );
}

class SearchResults {
  const SearchResults({required this.query, this.books = const [], this.pages = const []});

  final String query;
  final List<Book> books;
  final List<PageHit> pages;

  bool get isEmpty => books.isEmpty && pages.isEmpty;

  factory SearchResults.fromJson(Map<String, dynamic> json) => SearchResults(
    query: json['query'] as String? ?? '',
    books: [
      for (final b in (json['book_matches'] as List? ?? const []))
        Book.fromJson(b as Map<String, dynamic>),
    ],
    pages: [
      for (final p in (json['results'] as List? ?? const []))
        PageHit.fromJson(p as Map<String, dynamic>),
    ],
  );
}

class Bookmark {
  const Bookmark({required this.id, required this.bookId, required this.page, this.label});

  final String id;
  final String bookId;
  final int page;
  final String? label;

  factory Bookmark.fromJson(Map<String, dynamic> json) => Bookmark(
    id: '${json['id']}',
    bookId: '${json['book_id']}',
    page: _int(json['page_number']) ?? 1,
    label: json['label'] as String?,
  );
}

class Character {
  const Character({
    required this.id,
    required this.name,
    this.schemaName,
    this.system,
    this.campaignName,
    this.ownerName,
    this.owned = true,
    this.editable = true,
    this.status = 'active',
    this.portraitVersion,
    this.hasPortrait = false,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String? schemaName;
  final String? system;
  final String? campaignName;
  final String? ownerName;
  final bool owned;
  final bool editable;

  /// `active`, `retired` or `dead`.
  final String status;
  final int? portraitVersion;
  final bool hasPortrait;
  final DateTime? updatedAt;

  factory Character.fromJson(Map<String, dynamic> json) => Character(
    id: '${json['id']}',
    name: json['name'] as String? ?? '',
    schemaName: json['schema_name'] as String?,
    system: json['system'] as String?,
    campaignName: json['campaign_name'] as String?,
    ownerName: json['owner_name'] as String?,
    owned: json['owned'] as bool? ?? true,
    editable: json['editable'] as bool? ?? true,
    status: json['status'] as String? ?? 'active',
    portraitVersion: _int(json['portrait_version']),
    hasPortrait: (json['portrait_path'] as String?)?.isNotEmpty ?? false,
    updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
  );
}
