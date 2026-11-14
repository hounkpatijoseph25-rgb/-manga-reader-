/// Progression de lecture d'un manga : chapitres lus + dernière page de chaque chapitre.
class MangaProgress {
  const MangaProgress({
    this.readChapterIds = const {},
    this.lastPage = const {},
  });

  final Set<String> readChapterIds;
  final Map<String, int> lastPage;

  bool isRead(String chapterId) => readChapterIds.contains(chapterId);
  int pageOf(String chapterId) => lastPage[chapterId] ?? 0;
  bool get isEmpty => readChapterIds.isEmpty && lastPage.isEmpty;

  factory MangaProgress.fromJson(Map<String, dynamic> json) {
    final pages = (json['pages'] as Map?) ?? const {};
    return MangaProgress(
      readChapterIds: ((json['read'] as List?) ?? const [])
          .map((e) => '$e')
          .toSet(),
      lastPage: {
        for (final e in pages.entries) '${e.key}': (e.value as num).toInt(),
      },
    );
  }

  Map<String, dynamic> toJson() => {
    'read': readChapterIds.toList(),
    'pages': lastPage,
  };
}
