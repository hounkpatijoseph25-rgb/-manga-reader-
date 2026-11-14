import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/download_record.dart';

/// Index persistant des chapitres téléchargés.
///
/// Les images vivent dans le dossier `downloads/` ; cette boîte Hive garde les
/// métadonnées (manga, chapitre, nombre de pages, taille) pour pouvoir lister
/// et relire les chapitres même quand l'application est hors connexion.
class DownloadRepository {
  DownloadRepository(this._box);

  final Box<String> _box;

  List<DownloadRecord> all() {
    final result = <DownloadRecord>[];
    for (final raw in _box.values) {
      try {
        result.add(
          DownloadRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>),
        );
      } catch (_) {
        // enregistrement illisible : on l'ignore
      }
    }
    result.sort((a, b) {
      final byManga = a.manga.title.toLowerCase().compareTo(
        b.manga.title.toLowerCase(),
      );
      if (byManga != 0) return byManga;
      return a.chapter.numberValue.compareTo(b.chapter.numberValue);
    });
    return result;
  }

  /// Émet la liste complète à chaque modification de la base.
  Stream<List<DownloadRecord>> watch() async* {
    yield all();
    await for (final _ in _box.watch()) {
      yield all();
    }
  }

  DownloadRecord? get(String key) {
    final raw = _box.get(key);
    if (raw == null) return null;
    try {
      return DownloadRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(DownloadRecord record) =>
      _box.put(record.key, jsonEncode(record.toJson()));

  Future<void> remove(String key) => _box.delete(key);

  /// Supprime les enregistrements d'un manga (tous ses chapitres).
  Future<void> removeManga(String mangaKey) async {
    final keys = [
      for (final entry in _box.toMap().entries)
        if (_mangaKeyOf(entry.value) == mangaKey) entry.key,
    ];
    if (keys.isEmpty) return;
    await _box.deleteAll(keys);
  }

  Future<void> clear() => _box.clear();

  String? _mangaKeyOf(Object? raw) {
    if (raw is! String) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final manga = json['manga'] as Map?;
      if (manga == null) return null;
      return '${manga['sourceId']}:${manga['id']}';
    } catch (_) {
      return null;
    }
  }
}
