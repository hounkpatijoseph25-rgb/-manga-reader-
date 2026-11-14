import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/chapter.dart';
import '../models/history_entry.dart';
import '../models/manga.dart';

class HistoryRepository {
  HistoryRepository(this._box);

  final Box<String> _box;

  List<HistoryEntry> all() {
    final result = <HistoryEntry>[];
    for (final raw in _box.values) {
      try {
        result.add(
          HistoryEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>),
        );
      } catch (_) {
        // entrée illisible : on l'ignore
      }
    }
    result.sort((a, b) => b.readAt.compareTo(a.readAt));
    return result;
  }

  Stream<List<HistoryEntry>> watch() async* {
    yield all();
    await for (final _ in _box.watch()) {
      yield all();
    }
  }

  Future<void> record(Manga manga, Chapter chapter, int page) {
    final entry = HistoryEntry(
      manga: manga,
      chapterId: chapter.id,
      chapterTitle: chapter.displayTitle,
      page: page,
      readAt: DateTime.now(),
    );
    return _box.put(manga.key, jsonEncode(entry.toJson()));
  }

  Future<void> remove(String mangaKey) => _box.delete(mangaKey);

  Future<void> clear() async {
    await _box.clear();
  }
}
