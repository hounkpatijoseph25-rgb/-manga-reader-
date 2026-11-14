import 'package:dio/dio.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/downloads/download_service.dart';
import '../data/models/category.dart';
import '../data/models/history_entry.dart';
import '../data/models/library_entry.dart';
import '../data/models/manga_progress.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/history_repository.dart';
import '../data/repositories/library_repository.dart';
import '../data/repositories/progress_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/sources/local_source.dart';
import '../data/sources/manga_source.dart';
import '../data/sources/mangadex_source.dart';
import '../data/storage/storage_service.dart';
import 'constants.dart';

// ------------------------------------------------------------------ stockage

/// Fourni dans main() une fois la base de données ouverte.
final storageProvider = Provider<StorageService>((ref) {
  throw UnimplementedError('storageProvider doit être fourni dans main()');
});

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  final s = ref.watch(storageProvider);
  return LibraryRepository(s.libraryBox, s.chapterIdsBox);
});

final progressRepositoryProvider = Provider<ProgressRepository>(
  (ref) => ProgressRepository(ref.watch(storageProvider).progressBox),
);

final historyRepositoryProvider = Provider<HistoryRepository>(
  (ref) => HistoryRepository(ref.watch(storageProvider).historyBox),
);

final categoryRepositoryProvider = Provider<CategoryRepository>(
  (ref) => CategoryRepository(ref.watch(storageProvider).categoriesBox),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(storageProvider).settingsBox),
);

// Flux réactifs : l'interface se met à jour toute seule quand la base change.

final libraryEntriesProvider = StreamProvider<List<LibraryEntry>>(
  (ref) => ref.watch(libraryRepositoryProvider).watch(),
);

/// Clés (source:id) des mangas présents dans la bibliothèque.
final libraryKeysProvider = Provider<Set<String>>((ref) {
  final entries =
      ref.watch(libraryEntriesProvider).value ?? const <LibraryEntry>[];
  return {for (final e in entries) e.manga.key};
});

final categoriesProvider = StreamProvider<List<Category>>(
  (ref) => ref.watch(categoryRepositoryProvider).watch(),
);

final allProgressProvider = StreamProvider<Map<String, MangaProgress>>(
  (ref) => ref.watch(progressRepositoryProvider).watchAll(),
);

final mangaProgressProvider = StreamProvider.autoDispose
    .family<MangaProgress, String>(
      (ref, mangaKey) =>
          ref.watch(progressRepositoryProvider).watchOne(mangaKey),
    );

final historyProvider = StreamProvider<List<HistoryEntry>>(
  (ref) => ref.watch(historyRepositoryProvider).watch(),
);

// ------------------------------------------------------------------- réglages

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(settingsRepositoryProvider).load();

  void _update(AppSettings next) {
    state = next;
    ref.read(settingsRepositoryProvider).save(next);
  }

  void setThemeMode(ThemeMode mode) => _update(state.copyWith(themeMode: mode));
  void setSeedIndex(int index) => _update(state.copyWith(seedIndex: index));
  void setReaderMode(ReaderMode mode) =>
      _update(state.copyWith(readerMode: mode));
  void setContentLanguage(String code) =>
      _update(state.copyWith(contentLanguage: code));
  void setDataSaver(bool value) => _update(state.copyWith(dataSaver: value));
  void setLibraryGrid(bool value) =>
      _update(state.copyWith(libraryGrid: value));

  void togglePinned(String sourceId) {
    final pinned = [...state.pinnedSources];
    if (!pinned.remove(sourceId)) pinned.add(sourceId);
    _update(state.copyWith(pinnedSources: pinned));
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

// -------------------------------------------------------------------- réseau

final dioProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'User-Agent': AppConstants.userAgent},
    ),
  );
});

final downloadServiceProvider = Provider<DownloadService>(
  (ref) => DownloadService(ref.watch(dioProvider)),
);

// ------------------------------------------------------------------- sources

final mangaDexSourceProvider = Provider<MangaSource>((ref) {
  return MangaDexSource(
    ref.watch(dioProvider),
    language: () => ref.read(settingsProvider).contentLanguage,
    dataSaver: () => ref.read(settingsProvider).dataSaver,
  );
});

final localSourceProvider = Provider<LocalMangaSource>((ref) => LocalMangaSource());

/// Les extensions externes doivent fournir un adaptateur compilé dans l'application.
final sourcesProvider = Provider<List<MangaSource>>((ref) {
  return [ref.watch(mangaDexSourceProvider), ref.watch(localSourceProvider)];
});

final sourceByIdProvider = Provider.family<MangaSource?, String>((ref, id) {
  for (final source in ref.watch(sourcesProvider)) {
    if (source.id == id) return source;
  }
  return null;
});
