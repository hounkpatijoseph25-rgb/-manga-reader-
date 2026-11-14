import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/models/chapter.dart';
import '../../data/models/manga.dart';

/// État des téléchargements : chapitres terminés, en cours (avec progression) ou en échec.
class DownloadsState {
  const DownloadsState({
    this.done = const {},
    this.active = const {},
    this.failed = const {},
  });

  final Set<String> done;
  final Map<String, double> active;
  final Set<String> failed;

  DownloadsState copyWith({
    Set<String>? done,
    Map<String, double>? active,
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

  /// Clé d'un chapitre dans l'état ("source:idChapitre").
  static String keyOf(Manga manga, Chapter chapter) =>
      '${manga.sourceId}:${chapter.id}';

  /// Regarde sur le disque quels chapitres de ce manga sont déjà téléchargés.
  Future<void> scan(Manga manga, List<Chapter> chapters) async {
    final service = ref.read(downloadServiceProvider);
    final folders = await service.downloadedFolders(manga);
    final found = <String>{
      for (final c in chapters)
        if (folders.contains(service.folderOf(c))) keyOf(manga, c),
    };
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
      active[key] = 0;
      failed.remove(key);
    }
    state = state.copyWith(active: active, failed: failed);
    _run();
  }

  Future<void> _run() async {
    if (_running) return;
    _running = true;
    final service = ref.read(downloadServiceProvider);
    while (_queue.isNotEmpty) {
      final job = _queue.removeAt(0);
      final key = keyOf(job.manga, job.chapter);
      try {
        final source = ref.read(sourceByIdProvider(job.manga.sourceId));
        if (source == null) throw StateError('Source introuvable.');
        await service.downloadChapter(
          source: source,
          manga: job.manga,
          chapter: job.chapter,
          onProgress: (p) =>
              state = state.copyWith(active: {...state.active, key: p}),
        );
        state = state.copyWith(
          done: {...state.done, key},
          active: {...state.active}..remove(key),
        );
      } catch (_) {
        state = state.copyWith(
          failed: {...state.failed, key},
          active: {...state.active}..remove(key),
        );
      }
    }
    _running = false;
  }

  Future<void> remove(Manga manga, Chapter chapter) async {
    await ref.read(downloadServiceProvider).deleteChapter(manga, chapter);
    state = state.copyWith(
      done: {...state.done}..remove(keyOf(manga, chapter)),
    );
  }

  /// À appeler après la suppression de tous les téléchargements.
  void clearDone() => state = state.copyWith(done: <String>{});
}

final downloadsProvider = NotifierProvider<DownloadsNotifier, DownloadsState>(
  DownloadsNotifier.new,
);
