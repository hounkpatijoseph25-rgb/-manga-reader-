import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/models/chapter.dart';
import '../../data/models/manga.dart';

/// Une sortie prévue : un manga et la date estimée de son prochain chapitre.
class UpcomingRelease {
  const UpcomingRelease({
    required this.manga,
    required this.date,
    this.count = 1,
    this.estimated = false,
  });

  final Manga manga;

  /// Date estimée du prochain chapitre.
  final DateTime date;

  /// Nombre de sorties prévues ce jour-là pour ce manga.
  final int count;

  /// Vrai quand l'estimation est peu fiable (trop peu de chapitres datés).
  final bool estimated;

  /// La date sans l'heure (clé de regroupement).
  DateTime get day => DateTime(date.year, date.month, date.day);
}

/// Calcule les prochaines sorties de tous les mangas de la bibliothèque.
///
/// La date est estimée à partir de la fréquence observée des derniers
/// chapitres publiés (récupérés dans le cache local, donc hors connexion) :
/// `prochain = dernière date + intervalle moyen`. Si l'intervalle amène dans le
/// passé, on avance par bonds entiers jusqu'à aujourd'hui ou plus tard.
final upcomingReleasesProvider = FutureProvider<List<UpcomingRelease>>((
  ref,
) async {
  final entries = await ref.watch(libraryEntriesProvider.future);
  final cache = ref.watch(chapterCacheRepositoryProvider);

  // 1) Lecture du JSON brut (rapide), puis décodage dans un isolate séparé :
  //    décoder ici tout le cache de la bibliothèque figeait l'interface à
  //    l'ouverture de l'onglet (et au démarrage, avant le correctif de
  //    `home_shell.dart`).
  final rawByKey = <String, String>{};
  for (final entry in entries) {
    final json = cache.raw(entry.manga.key);
    if (json != null) rawByKey[entry.manga.key] = json;
  }
  if (rawByKey.isEmpty) return const <UpcomingRelease>[];
  final parsed = await compute(_decodeChapterCache, rawByKey);

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final result = <UpcomingRelease>[];

  for (final entry in entries) {
    final chapters = parsed[entry.manga.key];
    if (chapters == null) continue;
    final dated = <Chapter>[
      for (final c in chapters)
        if (c.publishedAt != null) c,
    ]..sort((a, b) => a.publishedAt!.compareTo(b.publishedAt!));
    if (dated.isEmpty) continue;

    final interval = _estimateIntervalDays(dated);
    final lastDay = _dateOnly(dated.last.publishedAt!);
    var next = lastDay.add(Duration(days: interval));

    // Si la date estimée est déjà passée, on avance jusqu'à aujourd'hui.
    var guard = 0;
    while (next.isBefore(today) && guard < 1000) {
      next = next.add(Duration(days: interval));
      guard++;
    }
    if (next.isBefore(today)) continue;

    result.add(
      UpcomingRelease(
        manga: entry.manga,
        date: next,
        estimated: dated.length < 2,
      ),
    );
  }

  result.sort((a, b) => a.date.compareTo(b.date));
  return result;
});

/// Décodage du cache de chapitres, exécuté dans un isolate séparé.
Map<String, List<Chapter>> _decodeChapterCache(Map<String, String> rawByKey) {
  final out = <String, List<Chapter>>{};
  for (final entry in rawByKey.entries) {
    try {
      final list = jsonDecode(entry.value) as List;
      out[entry.key] = [
        for (final item in list)
          Chapter.fromJson((item as Map).cast<String, dynamic>()),
      ];
    } catch (_) {
      // Entrée illisible : ignorée.
    }
  }
  return out;
}

/// Intervalle moyen (en jours) entre les derniers chapitres datés.
int _estimateIntervalDays(List<Chapter> dated) {
  if (dated.length < 2) return 7; // pas assez de recul : une semaine par défaut
  final gaps = <int>[];
  for (var i = dated.length - 1; i > 0 && gaps.length < 5; i--) {
    final a = dated[i].publishedAt!;
    final b = dated[i - 1].publishedAt!;
    final days = a.difference(b).inDays;
    if (days > 0) gaps.add(days);
  }
  if (gaps.isEmpty) return 7;
  final avg = gaps.reduce((a, b) => a + b) / gaps.length;
  return avg.round().clamp(1, 365);
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
