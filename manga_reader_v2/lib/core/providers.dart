import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/downloads/download_service.dart';
import '../data/models/category.dart';
import '../data/models/download_record.dart';
import '../data/models/history_entry.dart';
import '../data/models/library_entry.dart';
import '../data/models/manga_progress.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/chapter_cache_repository.dart';
import '../data/repositories/cover_cache_repository.dart';
import '../data/repositories/download_queue_repository.dart';
import '../data/repositories/download_repository.dart';
import '../data/repositories/history_repository.dart';
import '../data/repositories/library_repository.dart';
import '../data/repositories/progress_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/updates_repository.dart';
import '../data/sources/downloads_source.dart';
import '../data/sources/fmteam_source.dart';
import '../data/sources/lelscan_source.dart';
import '../data/sources/local_source.dart';
import '../data/sources/manga_source.dart';
import '../data/sources/mangadex_source.dart';
import '../data/sources/poseidon_scans_source.dart';
import '../data/sources/scan_vf_source.dart';
import '../data/sources/sushiscan_source.dart';
import '../data/storage/storage_service.dart';
import 'backup.dart';
import 'constants.dart';
import 'utils/network_headers.dart';

// ------------------------------------------------------------------ stockage

/// Fourni dans main() une fois la base de données ouverte.
final storageProvider = Provider<StorageService>((ref) {
  throw UnimplementedError('storageProvider doit être fourni dans main()');
});

/// Sauvegarde / restauration de la base locale (fichier JSON).
final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(ref.watch(storageProvider)),
);

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

final downloadRepositoryProvider = Provider<DownloadRepository>(
  (ref) => DownloadRepository(ref.watch(storageProvider).downloadsBox),
);

/// File d'attente persistante des téléchargements (reprise après redémarrage).
final downloadQueueRepositoryProvider = Provider<DownloadQueueRepository>(
  (ref) => DownloadQueueRepository(ref.watch(storageProvider).downloadQueueBox),
);

final chapterCacheRepositoryProvider = Provider<ChapterCacheRepository>(
  (ref) => ChapterCacheRepository(ref.watch(storageProvider).chapterCacheBox),
);

/// Veille : chapitres repérés par la mise à jour automatique.
final updatesRepositoryProvider = Provider<UpdatesRepository>(
  (ref) => UpdatesRepository(ref.watch(storageProvider).updatesBox),
);

/// Chapitres non consultés, par manga (`clé → ids`), réactif.
final pendingUpdatesProvider = StreamProvider<Map<String, List<String>>>((
  ref,
) async* {
  final repository = ref.watch(updatesRepositoryProvider);
  yield repository.pending();
  await for (final _ in repository.watch()) {
    yield repository.pending();
  }
});

/// Nombre total de chapitres non consultés (badge de la bibliothèque).
final pendingUpdatesCountProvider = Provider<int>((ref) {
  final pending = ref.watch(pendingUpdatesProvider).valueOrNull;
  if (pending == null) return 0;
  var total = 0;
  for (final ids in pending.values) {
    total += ids.length;
  }
  return total;
});

/// Couvertures recopiées sur l'appareil (visibles hors connexion).
final coverCacheRepositoryProvider = Provider<CoverCacheRepository>(
  (ref) => CoverCacheRepository(ref.watch(dioProvider)),
);

/// Index des couvertures locales : l'interface se reconstruit dès qu'une
/// nouvelle couverture a été mise de côté.
class CoverIndexNotifier extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() {
    final repository = ref.read(coverCacheRepositoryProvider);
    Future<void>.microtask(() async {
      final map = await repository.load();
      if (map.isNotEmpty) state = map;
    });
    return repository.index;
  }

  /// Télécharge la couverture une seule fois, puis prévient l'interface.
  Future<void> ensure(String url) async {
    if (!url.startsWith('http')) return;
    final path = await ref
        .read(coverCacheRepositoryProvider)
        .ensure(url, headers: ref.read(urlHeadersProvider)(url));
    if (path != null && state[url] != path) {
      state = {...state, url: path};
    }
  }
}

final coverIndexProvider =
    NotifierProvider<CoverIndexNotifier, Map<String, String>>(
      CoverIndexNotifier.new,
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

/// Chapitres téléchargés, disponibles hors connexion.
final downloadsListProvider = StreamProvider<List<DownloadRecord>>(
  (ref) => ref.watch(downloadRepositoryProvider).watch(),
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

  /// Fréquence de la veille en heures (`0` = désactivée).
  void setUpdatesIntervalHours(int hours) =>
      _update(state.copyWith(updatesIntervalHours: hours));

  void togglePinned(String sourceId) {
    final pinned = [...state.pinnedSources];
    if (!pinned.remove(sourceId)) pinned.add(sourceId);
    _update(state.copyWith(pinnedSources: pinned));
  }

  /// Dossier de la bibliothèque locale (chaîne vide = aucun dossier importé).
  void setLocalRoot(String path) =>
      _update(state.copyWith(localRoot: path.trim()));

  /// Image de présentation choisie à la main pour un manga local.
  void setLocalCover(String mangaPath, String coverPath) {
    final covers = {...state.localCovers, mangaPath: coverPath};
    _update(state.copyWith(localCovers: covers));
  }

  /// Revenir à la couverture détectée automatiquement.
  void clearLocalCover(String mangaPath) {
    final covers = {...state.localCovers}..remove(mangaPath);
    _update(state.copyWith(localCovers: covers));
  }

  /// Dossier de destination des téléchargements (chaîne vide = interne).
  void setDownloadsDir(String path) {
    final trimmed = path.trim();
    _update(
      state.copyWith(
        downloadsDir: trimmed,
        downloadsDirMode: trimmed.isEmpty ? 'internal' : 'custom',
      ),
    );
  }

  void setDownloadsDirMode(String mode) =>
      _update(state.copyWith(downloadsDirMode: mode));

  void setShowNsfw(bool value) => _update(state.copyWith(showNsfw: value));

  void setNotificationsEnabled(bool value) =>
      _update(state.copyWith(notificationsEnabled: value));

  /// Garder l'écran allumé pendant la lecture.
  void setKeepScreenOn(bool value) =>
      _update(state.copyWith(keepScreenOn: value));

  /// Luminosité du lecteur (`0..1`) ; `-1` = luminosité du système.
  void setReaderBrightness(double value) =>
      _update(state.copyWith(readerBrightness: value));
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

/// Client dédié aux images de chapitres : plus de connexions simultanées que
/// le client des pages HTML, et des délais plus courts pour ne jamais bloquer
/// la file derrière une requête morte.
final downloadDioProvider = Provider<Dio>((ref) {
  final client = HttpClient()
    ..maxConnectionsPerHost = 16
    ..idleTimeout = const Duration(seconds: 20)
    ..connectionTimeout = const Duration(seconds: 15)
    ..autoUncompress = true;
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 15),
      persistentConnection: true,
      headers: {'User-Agent': AppConstants.userAgent},
    ),
  );
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () => client,
  );
  return dio;
});

final downloadServiceProvider = Provider<DownloadService>(
  (ref) => DownloadService(
    ref.watch(downloadDioProvider),
    () => ref.read(settingsProvider).downloadsDir,
  ),
);

// ------------------------------------------------------------------- sources

final mangaDexSourceProvider = Provider<MangaSource>((ref) {
  return MangaDexSource(
    ref.watch(dioProvider),
    language: () => ref.read(settingsProvider).contentLanguage,
    dataSaver: () => ref.read(settingsProvider).dataSaver,
  );
});

/// FMTeam (scraping HTML de fmteam.fr).
final fmteamSourceProvider = Provider<MangaSource>((ref) {
  return FmteamSource(ref.watch(dioProvider));
});

/// Sushiscan (scraping HTML de sushiscan.net).
final sushiscanSourceProvider = Provider<MangaSource>((ref) {
  return SushiscanSource(ref.watch(dioProvider));
});

/// Scan-VF (scraping HTML de scan-vf.net).
final scanVfSourceProvider = Provider<MangaSource>((ref) {
  return ScanVfSource(ref.watch(dioProvider));
});

/// Lelscan (scraping HTML de lelscan.net).
final lelscanSourceProvider = Provider<MangaSource>((ref) {
  return LelscanSource(ref.watch(dioProvider));
});

/// Poseidon Scans (Next.js de poseidon-scans.net).
final poseidonScansSourceProvider = Provider<MangaSource>((ref) {
  return PoseidonScansSource(ref.watch(dioProvider));
});

/// Source locale : le dossier est lu à chaque appel depuis les réglages,
/// il est donc conservé d'un lancement à l'autre.
final localSourceProvider = Provider<LocalMangaSource>(
  (ref) => LocalMangaSource(
    rootPath: () => ref.read(settingsProvider).localRoot,
    coverOverride: (mangaPath) =>
        ref.read(settingsProvider).localCovers[mangaPath],
    downloadsRoot: () => ref.read(downloadServiceProvider).downloadsRootPath,
  ),
);

/// Chapitres téléchargés : relus depuis l'index des téléchargements.
final downloadsSourceProvider = Provider<MangaSource>((ref) {
  return DownloadsSource(
    records: () => ref.read(downloadRepositoryProvider).all(),
    chapterPages: (manga, chapter) =>
        ref.read(downloadServiceProvider).localPages(manga, chapter),
  );
});

/// En-têtes à joindre à une image (Referer CDN, etc.).
final urlHeadersProvider = Provider<Map<String, String> Function(String)>(
  (ref) => headersForUrl,
);

/// MangaDex 18+ (même API que MangaDex, contenus érotiques/pornographiques).
final mangaDexAdultSourceProvider = Provider<MangaSource>((ref) {
  return MangaDexSource(
    ref.watch(dioProvider),
    language: () => ref.read(settingsProvider).contentLanguage,
    dataSaver: () => ref.read(settingsProvider).dataSaver,
    id: 'mangadex18',
    name: 'MangaDex 18+',
    description: 'MangaDex, contenus réservés aux adultes',
    adult: true,
    ratings: const ['erotica', 'pornographic'],
  );
});

/// Toutes les sources intégrées (y compris adultes).
final allSourcesProvider = Provider<List<MangaSource>>((ref) {
  return [
    ref.watch(mangaDexSourceProvider),
    ref.watch(fmteamSourceProvider),
    ref.watch(sushiscanSourceProvider),
    ref.watch(scanVfSourceProvider),
    ref.watch(lelscanSourceProvider),
    ref.watch(poseidonScansSourceProvider),
    ref.watch(mangaDexAdultSourceProvider),
    ref.watch(downloadsSourceProvider),
    ref.watch(localSourceProvider),
  ];
});

/// Les extensions externes doivent fournir un adaptateur compilé dans l'application.
/// Les sources adultes sont masquées sauf si l'option est activée.
final sourcesProvider = Provider<List<MangaSource>>((ref) {
  final showNsfw = ref.watch(settingsProvider.select((s) => s.showNsfw));
  final sources = ref.watch(allSourcesProvider);
  if (showNsfw) return sources;
  return [for (final s in sources) if (!s.isAdult) s];
});

final sourceByIdProvider = Provider.family<MangaSource?, String>((ref, id) {
  for (final source in ref.watch(allSourcesProvider)) {
    if (source.id == id) return source;
  }
  return null;
});
