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

  /// Enregistre la position dans un chapitre.
  ///
  /// [page] sert aux modes paginés, [offset] au mode webtoon (pixels). Si
  /// [read] est vrai, le chapitre est marqué comme lu et sa position oubliée.
  Future<void> savePosition({
    required String mangaKey,
    required String chapterId,
    required int page,
    required bool read,
    double? offset,
  }) async {
    final current = get(mangaKey);
    final readIds = {...current.readChapterIds};
    final pages = {...current.lastPage};
    final offsets = {...current.lastOffset};
    if (read) {
      readIds.add(chapterId);
      pages.remove(chapterId);
      offsets.remove(chapterId);
    } else {
      pages[chapterId] = page;
      if (offset != null) offsets[chapterId] = offset;
    }
    await _put(
      mangaKey,
      MangaProgress(
        readChapterIds: readIds,
        lastPage: pages,
        bookmarkedChapterIds: current.bookmarkedChapterIds,
        lastOffset: offsets,
      ),
    );
  }

  /// Enregistre uniquement la position de défilement (webtoon) sans toucher au
  /// statut « lu ». Appelée fréquemment pendant le défilement.
  Future<void> saveOffset({
    required String mangaKey,
    required String chapterId,
    required double offset,
  }) async {
    final current = get(mangaKey);
    if (current.isRead(chapterId)) return; // chapitre déjà terminé : on n'y revient pas
    final offsets = {...current.lastOffset, chapterId: offset};
    await _put(
      mangaKey,
      MangaProgress(
        readChapterIds: current.readChapterIds,
        lastPage: current.lastPage,
        bookmarkedChapterIds: current.bookmarkedChapterIds,
        lastOffset: offsets,
      ),
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
    final offsets = {...current.lastOffset};
    for (final id in chapterIds) {
      if (read) {
        readIds.add(id);
      } else {
        readIds.remove(id);
      }
      pages.remove(id);
      offsets.remove(id);
    }
    await _put(
      mangaKey,
      MangaProgress(
        readChapterIds: readIds,
        lastPage: pages,
        bookmarkedChapterIds: current.bookmarkedChapterIds,
        lastOffset: offsets,
      ),
    );
  }

  /// Ajoute ou retire des chapitres des favoris (marque-page).
  Future<void> setBookmarked(
    String mangaKey,
    Iterable<String> chapterIds,
    bool bookmarked,
  ) async {
    final current = get(mangaKey);
    final bookmarks = {...current.bookmarkedChapterIds};
    for (final id in chapterIds) {
      if (bookmarked) {
        bookmarks.add(id);
      } else {
        bookmarks.remove(id);
      }
    }
    await _put(
      mangaKey,
      MangaProgress(
        readChapterIds: current.readChapterIds,
        lastPage: current.lastPage,
        bookmarkedChapterIds: bookmarks,
        lastOffset: current.lastOffset,
      ),
    );
  }

  Future<void> _put(String mangaKey, MangaProgress progress) =>
      _box.put(mangaKey, jsonEncode(progress.toJson()));
}
