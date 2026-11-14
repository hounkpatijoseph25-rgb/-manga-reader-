import 'manga.dart';

/// Un manga enregistré dans la bibliothèque.
class LibraryEntry {
  const LibraryEntry({
    required this.manga,
    required this.addedAt,
    this.categoryIds = const [],
    this.chapterCount = 0,
  });

  final Manga manga;
  final DateTime addedAt;
  final List<String> categoryIds;
  final int chapterCount;

  LibraryEntry copyWith({
    Manga? manga,
    List<String>? categoryIds,
    int? chapterCount,
  }) {
    return LibraryEntry(
      manga: manga ?? this.manga,
      addedAt: addedAt,
      categoryIds: categoryIds ?? this.categoryIds,
      chapterCount: chapterCount ?? this.chapterCount,
    );
  }

  factory LibraryEntry.fromJson(Map<String, dynamic> json) {
    return LibraryEntry(
      manga: Manga.fromJson((json['manga'] as Map).cast<String, dynamic>()),
      addedAt:
          DateTime.tryParse((json['addedAt'] as String?) ?? '') ??
          DateTime.now(),
      categoryIds: ((json['categories'] as List?) ?? const [])
          .map((e) => '$e')
          .toList(),
      chapterCount: (json['chapterCount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'manga': manga.toJson(),
    'addedAt': addedAt.toIso8601String(),
    'categories': categoryIds,
    'chapterCount': chapterCount,
  };
}
