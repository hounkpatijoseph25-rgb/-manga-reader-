import 'chapter.dart';
import 'manga.dart';

/// Un chapitre entièrement téléchargé, avec assez d'informations pour être
/// affiché et relu sans aucune connexion réseau.
class DownloadRecord {
  const DownloadRecord({
    required this.manga,
    required this.chapter,
    required this.pageCount,
    required this.bytes,
    required this.downloadedAt,
  });

  final Manga manga;
  final Chapter chapter;
  final int pageCount;
  final int bytes;
  final DateTime downloadedAt;

  /// Même clé que celle utilisée par [DownloadsNotifier] ("source:id|chapitre").
  String get key => '${manga.key}|${chapter.id}';

  DownloadRecord copyWith({int? pageCount, int? bytes}) {
    return DownloadRecord(
      manga: manga,
      chapter: chapter,
      pageCount: pageCount ?? this.pageCount,
      bytes: bytes ?? this.bytes,
      downloadedAt: downloadedAt,
    );
  }

  factory DownloadRecord.fromJson(Map<String, dynamic> json) {
    return DownloadRecord(
      manga: Manga.fromJson((json['manga'] as Map).cast<String, dynamic>()),
      chapter: Chapter.fromJson(
        (json['chapter'] as Map).cast<String, dynamic>(),
      ),
      pageCount: (json['pageCount'] as num?)?.toInt() ?? 0,
      bytes: (json['bytes'] as num?)?.toInt() ?? 0,
      downloadedAt:
          DateTime.tryParse('${json['downloadedAt'] ?? ''}') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'manga': manga.toJson(),
    'chapter': chapter.toJson(),
    'pageCount': pageCount,
    'bytes': bytes,
    'downloadedAt': downloadedAt.toIso8601String(),
  };
}
