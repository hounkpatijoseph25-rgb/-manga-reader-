import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/manga_progress.dart';

class ProgressRepository {
  ProgressRepository(this._box);

  final Box<String> _box;

  MangaProgress get(String mangaKey) {
    final raw = _box.get(mangaKey);
    if (raw == null) return const MangaProgress();
    try {
      return MangaProgress.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const MangaProgress();
    }
  }

  Stream<MangaProgress> watchOne(String mangaKey) async* {
    yield get(mangaKey);
    await for (final _ in _box.watch(key: mangaKey)) {
      yield get(mangaKey);
    }
  }

  Map<String, MangaProgress> _all() => {
    for (final k in _box.keys) '$k': get('$k'),
  };

  Stream<Map<String, MangaProgress>> watchAll() async* {
    yield _all();
    await for (final _ in _box.watch()) {
      yield _all();
    }
  }

  /// Enregistre la position dans un chapitre. Si [read] est vrai, le chapitre est marqué comme lu.
  Future<void> savePosition({
    required String mangaKey,
    required String chapterId,
    required int page,
    required bool read,
  }) async {
    final current = get(mangaKey);
    final readIds = {...current.readChapterIds};
    final pages = {...current.lastPage};
    if (read) {
      readIds.add(chapterId);
      pages.remove(chapterId);
    } else {
      pages[chapterId] = page;
    }
    await _put(
      mangaKey,
      MangaProgress(readChapterIds: readIds, lastPage: pages),
    );
  }

  /// Marque une liste de chapitres comme lus (ou non lus).
  Future<void> setRead(
    String mangaKey,
    Iterable<String> chapterIds,
    bool read,
  ) async {
    final current = get(mangaKey);
    final readIds = {...current.readChapterIds};
    final pages = {...current.lastPage};
    for (final id in chapterIds) {
      if (read) {
        readIds.add(id);
      } else {
        readIds.remove(id);
      }
      pages.remove(id);
    }
    await _put(
      mangaKey,
      MangaProgress(readChapterIds: readIds, lastPage: pages),
    );
  }

  Future<void> _put(String mangaKey, MangaProgress progress) =>
      _box.put(mangaKey, jsonEncode(progress.toJson()));
}
