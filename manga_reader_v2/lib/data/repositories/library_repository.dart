import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/library_entry.dart';
import '../models/manga.dart';

class LibraryRepository {
  LibraryRepository(this._entries, this._chapterIds);

  final Box<String> _entries;
  final Box<String> _chapterIds;

  List<LibraryEntry> all() {
    final result = <LibraryEntry>[];
    for (final raw in _entries.values) {
      try {
        result.add(
          LibraryEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>),
        );
      } catch (_) {
        // entrée illisible : on l'ignore
      }
    }
    result.sort(
      (a, b) =>
          a.manga.title.toLowerCase().compareTo(b.manga.title.toLowerCase()),
    );
    return result;
  }

  /// Émet la liste complète à chaque modification de la base (stockage réactif).
  Stream<List<LibraryEntry>> watch() async* {
    yield all();
    await for (final _ in _entries.watch()) {
      yield all();
    }
  }

  bool contains(String key) => _entries.containsKey(key);

  LibraryEntry? get(String key) {
    final raw = _entries.get(key);
    if (raw == null) return null;
    try {
      return LibraryEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> add(Manga manga, {List<String> chapterIds = const []}) async {
    final existing = get(manga.key);
    final entry = LibraryEntry(
      manga: manga,
      addedAt: existing?.addedAt ?? DateTime.now(),
      categoryIds: existing?.categoryIds ?? const [],
      chapterCount: chapterIds.length,
    );
    await _put(entry);
    await _chapterIds.put(manga.key, jsonEncode(chapterIds));
  }

  Future<void> remove(String key) async {
    await _entries.delete(key);
    await _chapterIds.delete(key);
  }

  Future<void> setCategories(String key, List<String> categoryIds) async {
    final entry = get(key);
    if (entry == null) return;
    await _put(entry.copyWith(categoryIds: categoryIds));
  }

  /// Ids des chapitres connus d'un manga de la bibliothèque.
  List<String> chapterIds(String key) {
    final raw = _chapterIds.get(key);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List).map((e) => '$e').toList();
    } catch (_) {
      return const [];
    }
  }

  /// Met à jour la liste des chapitres (sert à calculer les badges "non lus").
  Future<void> saveChapterIds(String key, List<String> ids) async {
    final entry = get(key);
    if (entry == null) return;
    await _chapterIds.put(key, jsonEncode(ids));
    await _put(entry.copyWith(chapterCount: ids.length));
  }

  /// Si le manga est déjà en bibliothèque, rafraîchit ses infos et ses chapitres.
  Future<void> syncIfInLibrary(Manga manga, List<String> ids) async {
    final entry = get(manga.key);
    if (entry == null) return;
    await _chapterIds.put(manga.key, jsonEncode(ids));
    await _put(entry.copyWith(manga: manga, chapterCount: ids.length));
  }

  /// Met à jour les informations d'un manga déjà suivi (couverture comprise).
  Future<void> updateManga(Manga manga) async {
    final entry = get(manga.key);
    if (entry == null) return;
    await _put(entry.copyWith(manga: manga));
  }

  Future<void> _put(LibraryEntry entry) =>
      _entries.put(entry.manga.key, jsonEncode(entry.toJson()));
}
