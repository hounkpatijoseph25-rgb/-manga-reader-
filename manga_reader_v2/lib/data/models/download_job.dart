import 'chapter.dart';
import 'manga.dart';

/// Un téléchargement en attente, sérialisable pour survivre à la fermeture de
/// l'application (reprise automatique après une coupure ou un redémarrage).
class DownloadJob {
  const DownloadJob({
    required this.manga,
    required this.chapter,
    this.attempts = 0,
    this.nextAttemptAt,
    this.order,
  });

  final Manga manga;
  final Chapter chapter;

  /// Nombre de tentatives déjà effectuées (conservé pour le backoff).
  final int attempts;

  /// Instant avant lequel il ne faut pas réessayer (backoff après échec).
  final DateTime? nextAttemptAt;

  /// Position dans la file (0 = prochain chapitre). `null` pour les anciennes
  /// entrées créées avant l'ajout de la réorganisation : le dépôt leur attribue
  /// alors une position à la lecture.
  final int? order;

  /// Même clé que [DownloadsNotifier.keyOf] ("source:id|idChapitre").
  String get key => '${manga.key}|${chapter.id}';

  DownloadJob copyWith({
    int? attempts,
    DateTime? nextAttemptAt,
    bool clearNextAttemptAt = false,
    int? order,
  }) {
    return DownloadJob(
      manga: manga,
      chapter: chapter,
      attempts: attempts ?? this.attempts,
      nextAttemptAt: clearNextAttemptAt
          ? null
          : (nextAttemptAt ?? this.nextAttemptAt),
      order: order ?? this.order,
    );
  }

  factory DownloadJob.fromJson(Map<String, dynamic> json) {
    return DownloadJob(
      manga: Manga.fromJson((json['manga'] as Map).cast<String, dynamic>()),
      chapter: Chapter.fromJson(
        (json['chapter'] as Map).cast<String, dynamic>(),
      ),
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      nextAttemptAt: DateTime.tryParse('${json['nextAttemptAt'] ?? ''}'),
      order: (json['order'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
    'manga': manga.toJson(),
    'chapter': chapter.toJson(),
    'attempts': attempts,
    'nextAttemptAt': nextAttemptAt?.toIso8601String(),
    'order': order,
  };
}
