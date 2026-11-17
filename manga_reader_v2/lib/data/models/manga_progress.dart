/// Progression de lecture d'un manga :
/// - chapitres lus ;
/// - dernière page connue de chaque chapitre (modes paginés) ;
/// - dernière position de défilement (mode webtoon, en pixels) ;
/// - chapitres mis en favori (marque-page).
class MangaProgress {
  const MangaProgress({
    this.readChapterIds = const {},
    this.lastPage = const {},
    this.bookmarkedChapterIds = const {},
    this.lastOffset = const {},
  });

  final Set<String> readChapterIds;
  final Map<String, int> lastPage;

  /// Chapitres marqués d'un marque-page (« Favori » dans la sélection).
  final Set<String> bookmarkedChapterIds;

  /// Position de défilement vertical (webtoon) par chapitre, en pixels.
  final Map<String, double> lastOffset;

  bool isRead(String chapterId) => readChapterIds.contains(chapterId);
  int pageOf(String chapterId) => lastPage[chapterId] ?? 0;
  double offsetOf(String chapterId) => lastOffset[chapterId] ?? 0;
  bool isBookmarked(String chapterId) =>
      bookmarkedChapterIds.contains(chapterId);

  bool get isEmpty => readChapterIds.isEmpty && lastPage.isEmpty;

  factory MangaProgress.fromJson(Map<String, dynamic> json) {
    final pages = (json['pages'] as Map?) ?? const {};
    final offsets = (json['offsets'] as Map?) ?? const {};
    return MangaProgress(
      readChapterIds: ((json['read'] as List?) ?? const [])
          .map((e) => '$e')
          .toSet(),
      lastPage: {
        for (final e in pages.entries) '${e.key}': (e.value as num).toInt(),
      },
      bookmarkedChapterIds: ((json['bookmarked'] as List?) ?? const [])
          .map((e) => '$e')
          .toSet(),
      lastOffset: {
        for (final e in offsets.entries)
          '${e.key}': (e.value as num).toDouble(),
      },
    );
  }

  Map<String, dynamic> toJson() => {
    'read': readChapterIds.toList(),
    'pages': lastPage,
    'bookmarked': bookmarkedChapterIds.toList(),
    'offsets': lastOffset,
  };
}
