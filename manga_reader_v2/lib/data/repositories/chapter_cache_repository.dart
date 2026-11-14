import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/chapter.dart';

/// Dernière liste de chapitres connue pour chaque manga.
///
/// Elle est enregistrée à chaque chargement réussi de la fiche d'un manga et
/// sert de secours quand le réseau est indisponible : on peut alors ouvrir la
/// fiche et relire les chapitres déjà téléchargés.
class ChapterCacheRepository {
  ChapterCacheRepository(this._box);

  final Box<String> _box;

  List<Chapter> load(String mangaKey) {
    final raw = _box.get(mangaKey);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return [
        for (final item in list)
          Chapter.fromJson((item as Map).cast<String, dynamic>()),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(String mangaKey, List<Chapter> chapters) {
    return _box.put(
      mangaKey,
      jsonEncode([for (final c in chapters) c.toJson()]),
    );
  }

  Future<void> remove(String mangaKey) => _box.delete(mangaKey);
}
