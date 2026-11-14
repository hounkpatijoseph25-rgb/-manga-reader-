import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/background_downloads.dart';
import '../../core/providers.dart';
import '../../data/models/chapter.dart';
import '../../data/models/download_record.dart';
import '../../data/models/manga.dart';

/// Un téléchargement en cours (affiché avec sa progression).
class ActiveDownload {
  const ActiveDownload({
    required this.manga,
    required this.chapter,
    this.progress = 0,
  });

  final Manga manga;
  final Chapter chapter;
  final double progress;

  ActiveDownload copyWith({double? progress}) => ActiveDownload(
    manga: manga,
    chapter: chapter,
    progress: progress ?? this.progress,
  );
}

/// État des téléchargements : chapitres terminés, en cours (avec progression) ou en échec.
class DownloadsState {
  const DownloadsState({
    this.done = const {},
    this.active = const {},
    this.failed = const {},
  });

  final Set<String> done;
  final Map<String, ActiveDownload> active;
  final Set<String> failed;

  DownloadsState copyWith({
    Set<String>? done,
    Map<String, ActiveDownload>? active,
    Set<String>? failed,
  }) {
    return DownloadsState(
      done: done ?? this.done,
      active: active ?? this.active,
      failed: failed ?? this.failed,
    );
  }
}

class _Job {
  _Job(this.manga, this.chapter);

  final Manga manga;
  final Chapter chapter;
}

class DownloadsNotifier extends Notifier<DownloadsState> {
  final List<_Job> _queue = [];
  bool _running = false;

  @override
  DownloadsState build() => const DownloadsState();

  /// Clé d'un chapitre dans l'état ("source:id|idChapitre").
  static String keyOf(Manga manga, Chapter chapter) =>
      '${manga.key}|${chapter.id}';

  /// Regarde sur le disque quels chapitres de ce manga sont déjà téléchargés
  /// et complète l'index persistant si besoin (téléchargements plus anciens).
  Future<void> scan(Manga manga, List<Chapter> chapters) async {
    final service = ref.read(downloadServiceProvider);
    final repository = ref.read(downloadRepositoryProvider);
    final folders = await service.downloadedFolders(manga);
    final found = <String>{};
    for (final chapter in chapters) {
      if (!folders.contains(service.folderOf(chapter))) continue;
      final key = keyOf(manga, chapter);
      found.add(key);
      if (repository.get(key) == null) {
        await repository.save(
          DownloadRecord(
            manga: manga,
            chapter: chapter,
            pageCount: chapter.pageCount,
            bytes: await service.chapterSize(manga, chapter),
            downloadedAt: DateTime.now(),
          ),
        );
      }
    }
    state = state.copyWith(done: {...state.done, ...found});
  }

  /// Ajoute des chapitres à la file de téléchargement (un seul à la fois).
  void enqueue(Manga manga, List<Chapter> chapters) {
    final active = {...state.active};
    final failed = {...state.failed};
    for (final c in chapters) {
      final key = keyOf(manga, c);
      if (state.done.contains(key) || active.containsKey(key)) continue;
      _queue.add(_Job(manga, c));
      active[key] = ActiveDownload(manga: manga, chapter: c);
      failed.remove(key);
    }
    state = state.copyWith(active: active, failed: failed);
    // Le service de premier plan évite qu'Android gèle la file quand
    // l'utilisateur quitte l'application.
    if (_queue.isNotEmpty) {
      unawaited(BackgroundDownloads.start(text: _pendingText(active.length)));
    }
    _run();
  }

  static String _pendingText(int count) =>
      '$count chapitre${count > 1 ? 's' : ''} en attente';

  Future<void> _run() async {
    if (_running) return;
    _running = true;
    final service = ref.read(downloadServiceProvider);
    final repository = ref.read(downloadRepositoryProvider);
    while (_queue.isNotEmpty) {
      final job = _queue.removeAt(0);
      final key = keyOf(job.manga, job.chapter);
      try {
        final source = ref.read(sourceByIdProvider(job.manga.sourceId));
        if (source == null) throw StateError('Source introuvable.');
        var lastPercent = -1;
        final pageCount = await service.downloadChapter(
          source: source,
          manga: job.manga,
          chapter: job.chapter,
          onProgress: (p) {
            final current = state.active[key];
            if (current == null) return;
            state = state.copyWith(
              active: {...state.active, key: current.copyWith(progress: p)},
            );
            final percent = (p * 100).round();
            if (percent == lastPercent) return;
            lastPercent = percent;
            unawaited(
              BackgroundDownloads.update(
                '${job.manga.title} · ${job.chapter.displayTitle} · $percent %',
              ),
            );
          },
        );
        // L'index persistant permet de relire le chapitre sans réseau.
        await repository.save(
          DownloadRecord(
            manga: job.manga,
            chapter: job.chapter,
            pageCount: pageCount,
            bytes: await service.chapterSize(job.manga, job.chapter),
            downloadedAt: DateTime.now(),
          ),
        );
        state = state.copyWith(
          done: {...state.done, key},
          active: {...state.active}..remove(key),
        );
        unawaited(
          BackgroundDownloads.update(
            _queue.isEmpty ? 'Téléchargements terminés' : _pendingText(_queue.length),
          ),
        );
      } catch (_) {
        state = state.copyWith(
          failed: {...state.failed, key},
          active: {...state.active}..remove(key),
        );
      }
    }
    _running = false;
    // File vide : plus besoin de garder le processus éveillé.
    unawaited(BackgroundDownloads.stop());
  }

  Future<void> remove(Manga manga, Chapter chapter) async {
    await ref.read(downloadServiceProvider).deleteChapter(manga, chapter);
    await ref.read(downloadRepositoryProvider).remove(keyOf(manga, chapter));
    state = state.copyWith(
      done: {...state.done}..remove(keyOf(manga, chapter)),
    );
  }

  /// Supprime tous les fichiers et tout l'index des téléchargements.
  Future<void> clearAll() async {
    await ref.read(downloadServiceProvider).clearAll();
    await ref.read(downloadRepositoryProvider).clear();
    _queue.clear();
    state = const DownloadsState();
    unawaited(BackgroundDownloads.stop());
  }
}

final downloadsProvider = NotifierProvider<DownloadsNotifier, DownloadsState>(
  DownloadsNotifier.new,
);
