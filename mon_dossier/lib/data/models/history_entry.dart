import 'manga.dart';

/// Dernier chapitre lu pour un manga (une ligne par manga dans l'historique).
class HistoryEntry {
  const HistoryEntry({
    required this.manga,
    required this.chapterId,
    required this.chapterTitle,
    required this.page,
    required this.readAt,
  });

  final Manga manga;
  final String chapterId;
  final String chapterTitle;
  final int page;
  final DateTime readAt;

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    return HistoryEntry(
      manga: Manga.fromJson((json['manga'] as Map).cast<String, dynamic>()),
      chapterId: json['chapterId'] as String,
      chapterTitle: (json['chapterTitle'] as String?) ?? '',
      page: (json['page'] as num?)?.toInt() ?? 0,
      readAt:
          DateTime.tryParse((json['readAt'] as String?) ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'manga': manga.toJson(),
    'chapterId': chapterId,
    'chapterTitle': chapterTitle,
    'page': page,
    'readAt': readAt.toIso8601String(),
  };
}
