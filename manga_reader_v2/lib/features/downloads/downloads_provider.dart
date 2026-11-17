import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/background_downloads.dart';
import '../../core/providers.dart';
import '../../data/downloads/download_service.dart';
import '../../data/models/chapter.dart';
import '../../data/models/download_job.dart';
import '../../data/models/download_record.dart';
import '../../data/models/manga.dart';
import '../../data/repositories/download_repository.dart';

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

/// État des téléchargements : chapitres terminés, en cours, en attente ou en
/// échec.
class DownloadsState {
  const DownloadsState({
    this.done = const {},
    this.active = const {},
    this.queued = const {},
    this.failed = const {},
    this.paused = false,
  });

  final Set<String> done;
  final Map<String, ActiveDownload> active;

  /// Chapitres déjà acceptés mais pas encore commencés (ou en attente d'un
  /// nouvel essai après une erreur réseau).
  final Map<String, ActiveDownload> queued;

  final Set<String> failed;

  /// L'utilisateur a mis la file en pause.
  final bool paused;

  bool get hasWork => active.isNotEmpty || queued.isNotEmpty;

  DownloadsState copyWith({
    Set<String>? done,
    Map<String, ActiveDownload>? active,
    Map<String, ActiveDownload>? queued,
    Set<String>? failed,
    bool? paused,
  }) {
    return DownloadsState(
      done: done ?? this.done,
      active: active ?? this.active,
      queued: queued ?? this.queued,
      failed: failed ?? this.failed,
      paused: paused ?? this.paused,
    );
  }
}

enum _JobResult { done, retry, cancelled }

/// Gère la file de téléchargement des chapitres.
///
/// - **Un seul chapitre à la fois** : les pages d'un chapitre sont téléchargées
///   en parallèle, mais le chapitre suivant attend que le précédent soit fini ;
/// - La file est **persistée** en base locale : elle reprend automatiquement au
///   prochain démarrage après une coupure réseau, un arrêt de l'application ou
///   un redémarrage du téléphone ;
/// - Un échec est **réessayé avec un backoff** (5 s, 10 s, 20 s…) au lieu de
///   condamner le chapitre immédiatement ;
/// - La file peut être **mise en pause**, **réordonnée** et des chapitres
///   peuvent être **arrêtés** sans toucher aux téléchargements terminés ;
/// - Un service de premier plan Android garde le processus éveillé quand
///   l'application passe en arrière-plan et affiche la progression.
class DownloadsNotifier extends Notifier<DownloadsState> {
  /// Nombre de chapitres téléchargés simultanément.
  static const int maxChapterConcurrency = 1;

  /// Nombre d'essais d'un chapitre avant de le signaler en échec pour la
  /// session en cours. Il reste dans la file persistée et sera retenté au
  /// prochain lancement.
  static const int maxJobAttempts = 8;

  static const List<int> _retrySeconds = [5, 10, 20, 40, 80, 160, 300];
  static const String _pausedKey = 'downloadsPaused';

  final List<DownloadJob> _queue = [];
  bool _running = false;

  /// Incrémenté par « Tout supprimer » pour ignorer un téléchargement qui se
  /// termine juste après le nettoyage.
  int _generation = 0;

  DownloadJob? _activeJob;
  CancelToken? _activeToken;

  /// Chapitres dont l'utilisateur a demandé l'arrêt pendant qu'ils étaient
  /// actifs. Ils sont nettoyés quand l'annulation HTTP est terminée.
  final Set<String> _stoppedKeys = {};

  /// Réveille la boucle quand la pause ou un ajout doit être pris en compte
  /// sans attendre la fin du backoff.
  Completer<void>? _sleepWake;

  @override
  DownloadsState build() {
    final box = ref.read(storageProvider).settingsBox;
    return DownloadsState(paused: box.get(_pausedKey) == true);
  }

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

  /// Ajoute des chapitres à la file de téléchargement.
  void enqueue(Manga manga, List<Chapter> chapters) {
    final failed = {...state.failed};
    final added = <DownloadJob>[];
    for (final c in chapters) {
      final key = keyOf(manga, c);
      if (state.done.contains(key) ||
          state.active.containsKey(key) ||
          state.queued.containsKey(key) ||
          _queue.any((job) => job.key == key)) {
        continue;
      }
      final job = DownloadJob(manga: manga, chapter: c, order: _nextOrder);
      _queue.add(job);
      added.add(job);
      failed.remove(key);
    }
    if (added.isEmpty) return;
    state = state.copyWith(queued: _queuedFromQueue(), failed: failed);
    // La file est écrite en base AVANT de commencer : elle survit à un arrêt.
    unawaited(ref.read(downloadQueueRepositoryProvider).addAll(added));
    _wakeLoop();
    if (_queue.isEmpty || state.paused) return;
    // Le service de premier plan évite qu'Android gèle la file quand
    // l'utilisateur quitte l'application.
    _startBackground();
    _run();
  }

  /// Reprend la file persistée au démarrage de l'application.
  ///
  /// Appelée une fois depuis `main()` : tout ce qui restait en attente après une
  /// coupure réseau ou un redémarrage est relancé automatiquement.
  Future<void> resumePending() async {
    final queueRepo = ref.read(downloadQueueRepositoryProvider);
    final pending = queueRepo.all();
    if (pending.isEmpty) return;

    final queued = {...state.queued};
    final failed = {...state.failed};
    final restored = <DownloadJob>[];
    for (final stored in pending) {
      final key = stored.key;
      if (state.done.contains(key) ||
          state.active.containsKey(key) ||
          queued.containsKey(key) ||
          _queue.any((job) => job.key == key)) {
        continue;
      }
      // Nouvelle session : on redonne sa chance à un chapitre qui avait
      // épuisé ses essais lors du lancement précédent.
      final job = stored.copyWith(
        attempts: 0,
        clearNextAttemptAt: true,
        order: _nextOrder,
      );
      _queue.add(job);
      restored.add(job);
      queued[key] = ActiveDownload(manga: job.manga, chapter: job.chapter);
      failed.remove(key);
    }
    if (restored.isNotEmpty) {
      _renumberQueue();
      await queueRepo.addAll(_queue);
      state = state.copyWith(queued: _queuedFromQueue(), failed: failed);
    }
    if (_queue.isEmpty || state.paused) return;
    _startBackground();
    unawaited(_run());
  }

  /// Met la file en pause. Le chapitre actif est annulé puis remis en tête de
  /// file : sa progression partielle est conservée et il reprendra au même
  /// endroit.
  Future<void> pause() async {
    if (state.paused) return;
    state = state.copyWith(paused: true);
    await _persistPaused(true);
    _wakeLoop();
    final token = _activeToken;
    if (token != null && !token.isCancelled) token.cancel('Pause');
    await BackgroundDownloads.stop(shouldStop: () => state.paused);
  }

  /// Relance la file après une pause.
  Future<void> resume() async {
    if (!state.paused) return;
    state = state.copyWith(paused: false);
    await _persistPaused(false);
    if (!state.hasWork && _queue.isEmpty) return;
    _startBackground();
    unawaited(_run());
  }

  /// Déplace un chapitre vers le haut (`delta = -1`) ou le bas (`delta = 1`).
  void moveQueued(String key, int delta) {
    final index = _queue.indexWhere((job) => job.key == key);
    if (index < 0) return;
    final target = (index + delta).clamp(0, _queue.length - 1).toInt();
    if (target == index) return;
    final job = _queue.removeAt(index);
    _queue.insert(target, job);
    _renumberQueue();
    state = state.copyWith(queued: _queuedFromQueue());
    unawaited(ref.read(downloadQueueRepositoryProvider).addAll(_queue));
    _wakeLoop();
  }

  /// Réordonne les chapitres en attente par numéro de chapitre croissant :
  /// le chapitre au plus petit numéro sera téléchargé en premier.
  ///
  /// L'ordre est persisté pour survivre à un redémarrage. Le chapitre en cours
  /// de téléchargement n'est pas affecté.
  void sortQueued() {
    if (_queue.length < 2) return;
    _queue.sort((a, b) {
      final byNumber = a.chapter.numberValue.compareTo(b.chapter.numberValue);
      if (byNumber != 0) return byNumber;
      final byManga = a.manga.key.compareTo(b.manga.key);
      if (byManga != 0) return byManga;
      return a.chapter.id.compareTo(b.chapter.id);
    });
    _renumberQueue();
    state = state.copyWith(queued: _queuedFromQueue());
    unawaited(ref.read(downloadQueueRepositoryProvider).addAll(_queue));
    _wakeLoop();
  }

  /// Arrête les chapitres indiqués (actif ou en attente) sans toucher aux
  /// chapitres déjà terminés.
  Future<void> stopJobs(Set<String> keys) async {
    if (keys.isEmpty) return;
    final queueRepo = ref.read(downloadQueueRepositoryProvider);
    final service = ref.read(downloadServiceProvider);
    final repository = ref.read(downloadRepositoryProvider);
    final storedJobs = {for (final job in queueRepo.all()) job.key: job};

    final stoppedActive = <String>{};
    for (final key in keys) {
      if (state.active.containsKey(key)) {
        stoppedActive.add(key);
        _stoppedKeys.add(key);
        if (_activeJob?.key == key) {
          final token = _activeToken;
          if (token != null && !token.isCancelled) {
            token.cancel('Arrêt demandé');
          }
        }
        // La suppression des fichiers attend la fin de l'écriture en cours.
        await queueRepo.remove(key);
        await repository.remove(key);
        continue;
      }

      final active = state.queued[key] ?? state.active[key];
      final job = storedJobs[key] ?? _jobInQueue(key);
      _queue.removeWhere((queued) => queued.key == key);
      if (active != null) {
        await service.deleteChapter(active.manga, active.chapter);
      } else if (job != null) {
        await service.deleteChapter(job.manga, job.chapter);
      }
      await repository.remove(key);
      await queueRepo.remove(key);
    }

    _renumberQueue();
    if (_queue.isNotEmpty) {
      await queueRepo.addAll(_queue);
    }
    state = state.copyWith(
      active: {...state.active}
        ..removeWhere((key, _) => stoppedActive.contains(key)),
      queued: _queuedFromQueue(),
      failed: {...state.failed}..removeAll(keys),
    );
    _wakeLoop();
    if (_queue.isEmpty && state.active.isEmpty) {
      unawaited(
        BackgroundDownloads.stop(shouldStop: () => _queue.isEmpty && !_running),
      );
    }
  }

  /// Arrête tout ce qui est en cours ou en attente, y compris les chapitres
  /// signalés en échec qui seraient autrement repris au prochain lancement.
  Future<void> stopAll() async {
    final keys = <String>{
      for (final job in _queue) job.key,
      ...state.active.keys,
      ...state.queued.keys,
      ...state.failed,
    };
    if (keys.isEmpty) return;
    await stopJobs(keys);
  }

  static String _pendingText(int count) =>
      '$count chapitre${count > 1 ? 's' : ''} en attente';

  /// Total des chapitres pas encore terminés (actif + file).
  int get _remaining => _queue.length + state.active.length;

  int get _nextOrder {
    var max = -1;
    for (final job in _queue) {
      final order = job.order;
      if (order != null && order > max) max = order;
    }
    return max + 1;
  }

  static Duration _retryDelay(int attempts) {
    final index = (attempts - 1).clamp(0, _retrySeconds.length - 1).toInt();
    return Duration(seconds: _retrySeconds[index]);
  }

  Future<void> _persistPaused(bool value) async {
    await ref.read(storageProvider).settingsBox.put(_pausedKey, value);
  }

  void _startBackground() {
    if (state.paused) return;
    unawaited(
      BackgroundDownloads.start(
        title: 'Téléchargements ($_remaining)',
        text: _pendingText(_remaining),
      ),
    );
  }

  Future<void> _sleep(Duration duration) async {
    if (duration <= Duration.zero) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      return;
    }
    final wake = Completer<void>();
    _sleepWake = wake;
    await Future.any<void>([Future<void>.delayed(duration), wake.future]);
    if (identical(_sleepWake, wake)) _sleepWake = null;
  }

  void _wakeLoop() {
    final wake = _sleepWake;
    _sleepWake = null;
    if (wake != null && !wake.isCompleted) wake.complete();
  }

  /// Traite la file, **un chapitre à la fois**.
  Future<void> _run() async {
    if (_running || state.paused) return;
    _running = true;
    try {
      while (_queue.isNotEmpty && !state.paused) {
        final now = DateTime.now();
        final index = _queue.indexWhere(
          (job) =>
              job.nextAttemptAt == null || !job.nextAttemptAt!.isAfter(now),
        );
        if (index < 0) {
          // Tous les chapitres restants attendent leur backoff : on dort par
          // petits pas pour pouvoir démarrer un ajout manuel sans attendre.
          final next = _queue
              .map((job) => job.nextAttemptAt!)
              .reduce((a, b) => a.isBefore(b) ? a : b);
          final wait = next.difference(now);
          final sleep = wait > const Duration(seconds: 5)
              ? const Duration(seconds: 5)
              : wait;
          await _sleep(sleep);
          continue;
        }

        final job = _queue.removeAt(index);
        final generation = _generation;
        final token = CancelToken();
        _activeJob = job;
        _activeToken = token;
        _markActive(job);

        _JobResult result;
        try {
          result = await _processJob(job, generation, token);
        } finally {
          if (_activeJob?.key == job.key) _activeJob = null;
          if (identical(_activeToken, token)) _activeToken = null;
        }

        if (generation != _generation) {
          // « Tout supprimer » est passé pendant le téléchargement : le
          // chapitre a pu être réécrit sur le disque après le nettoyage.
          await _cleanupFilesOnly(job);
          continue;
        }

        if (result == _JobResult.cancelled) {
          if (_stoppedKeys.remove(job.key)) {
            await _cleanupStopped(job);
            continue;
          }
          await _requeuePaused(job);
          continue;
        }
        if (result == _JobResult.done) {
          // L'arrêt a pu être demandé pendant l'écriture de l'index final.
          if (_stoppedKeys.remove(job.key)) {
            await _cleanupStopped(job);
          }
          continue;
        }

        final attempts = job.attempts + 1;
        if (attempts >= maxJobAttempts) {
          _markFailed(job);
          // La tâche reste dans la file persistée : au prochain lancement,
          // `resumePending` lui redonnera des essais. On ne bloque pas la
          // session en cours derrière un chapitre durablement cassé.
          continue;
        }

        final retry = job.copyWith(
          attempts: attempts,
          nextAttemptAt: DateTime.now().add(_retryDelay(attempts)),
          order: _nextOrder,
        );
        _queue.add(retry);
        await ref.read(downloadQueueRepositoryProvider).addAll([retry]);
        _markQueued(retry);
        unawaited(
          BackgroundDownloads.update(
            title: 'Téléchargements ($_remaining)',
            text: _pendingText(_remaining),
          ),
        );
      }
    } finally {
      _running = false;
      if (state.paused) {
        unawaited(BackgroundDownloads.stop(shouldStop: () => state.paused));
      } else if (_queue.isNotEmpty) {
        // Un ajout a eu lieu pendant que la boucle se terminait.
        unawaited(Future<void>.microtask(_run));
      } else {
        // File vide : plus besoin de garder le processus éveillé.
        unawaited(
          BackgroundDownloads.stop(
            shouldStop: () => _queue.isEmpty && !_running,
          ),
        );
      }
    }
  }

  Future<_JobResult> _processJob(
    DownloadJob job,
    int generation,
    CancelToken token,
  ) async {
    final key = job.key;
    final service = ref.read(downloadServiceProvider);
    final repository = ref.read(downloadRepositoryProvider);
    final queueRepo = ref.read(downloadQueueRepositoryProvider);
    try {
      if (generation != _generation || _stoppedKeys.contains(key)) {
        return _JobResult.cancelled;
      }
      // Déjà entièrement téléchargé (reprise) : aucun travail à refaire.
      if (await service.localPages(job.manga, job.chapter) != null) {
        if (generation != _generation || _stoppedKeys.contains(key)) {
          return _JobResult.cancelled;
        }
        await _markDone(job, service, repository);
        await queueRepo.remove(key);
        return _JobResult.done;
      }
      final source = ref.read(sourceByIdProvider(job.manga.sourceId));
      if (source == null) throw StateError('Source introuvable.');

      unawaited(
        BackgroundDownloads.update(
          title: 'Téléchargements ($_remaining)',
          text: '${job.manga.title} · ${job.chapter.displayTitle}',
        ),
      );

      var lastPercent = -1;
      final pageCount = await service.downloadChapter(
        source: source,
        manga: job.manga,
        chapter: job.chapter,
        cancelToken: token,
        // `onProgress` est appelé à CHAQUE page téléchargée : mettre à jour
        // l'état (et donc l'interface) à chaque page provoquait des centaines de
        // reconstructions par chapitre. On ne le fait qu'au pourcentage près.
        onProgress: (p) {
          if (generation != _generation) return;
          final percent = (p * 100).round();
          if (percent == lastPercent) return;
          lastPercent = percent;
          final current = state.active[key];
          if (current != null) {
            state = state.copyWith(
              active: {
                ...state.active,
                key: current.copyWith(progress: p),
              },
            );
          }
          unawaited(
            BackgroundDownloads.update(
              title: 'Téléchargements ($_remaining)',
              text:
                  '${job.manga.title} · ${job.chapter.displayTitle} · '
                  '$percent %',
            ),
          );
        },
      );

      if (generation != _generation || _stoppedKeys.contains(key)) {
        return _JobResult.cancelled;
      }
      if (token.isCancelled) return _JobResult.cancelled;

      await _markDone(job, service, repository, pageCount: pageCount);
      await queueRepo.remove(key);
      return _JobResult.done;
    } catch (error, stack) {
      if (generation != _generation ||
          _stoppedKeys.contains(key) ||
          token.isCancelled) {
        return _JobResult.cancelled;
      }
      debugPrint(
        'Téléchargement échoué (${job.manga.title} · '
        '${job.chapter.displayTitle}) : $error\n$stack',
      );
      return _JobResult.retry;
    }
  }

  /// Remet le chapitre actif en tête de file après une pause, sans compter
  /// d'échec supplémentaire.
  Future<void> _requeuePaused(DownloadJob job) async {
    _queue.removeWhere((queued) => queued.key == job.key);
    _queue.insert(0, job.copyWith(order: 0, clearNextAttemptAt: true));
    _renumberQueue();
    state = state.copyWith(
      active: {...state.active}..remove(job.key),
      queued: _queuedFromQueue(),
    );
    await ref.read(downloadQueueRepositoryProvider).addAll(_queue);
  }

  Future<void> _cleanupStopped(DownloadJob job) async {
    final key = job.key;
    await ref
        .read(downloadServiceProvider)
        .deleteChapter(job.manga, job.chapter);
    await ref.read(downloadRepositoryProvider).remove(key);
    await ref.read(downloadQueueRepositoryProvider).remove(key);
    state = state.copyWith(
      done: {...state.done}..remove(key),
      active: {...state.active}..remove(key),
      queued: {...state.queued}..remove(key),
      failed: {...state.failed}..remove(key),
    );
  }

  Future<void> _cleanupFilesOnly(DownloadJob job) async {
    try {
      await ref
          .read(downloadServiceProvider)
          .deleteChapter(job.manga, job.chapter);
    } catch (_) {
      // Le nettoyage global a peut-être déjà supprimé le dossier.
    }
  }

  void _renumberQueue() {
    for (var i = 0; i < _queue.length; i++) {
      _queue[i] = _queue[i].copyWith(order: i);
    }
  }

  DownloadJob? _jobInQueue(String key) {
    for (final job in _queue) {
      if (job.key == key) return job;
    }
    return null;
  }

  Map<String, ActiveDownload> _queuedFromQueue() => {
    for (final job in _queue)
      job.key: ActiveDownload(manga: job.manga, chapter: job.chapter),
  };

  void _markActive(DownloadJob job) {
    final key = job.key;
    final item =
        state.queued[key] ??
        ActiveDownload(manga: job.manga, chapter: job.chapter);
    state = state.copyWith(
      active: {...state.active, key: item},
      queued: {...state.queued}..remove(key),
    );
  }

  void _markQueued(DownloadJob job) {
    final key = job.key;
    state = state.copyWith(
      active: {...state.active}..remove(key),
      queued: {
        ...state.queued,
        key: ActiveDownload(manga: job.manga, chapter: job.chapter),
      },
    );
  }

  void _markFailed(DownloadJob job) {
    final key = job.key;
    state = state.copyWith(
      active: {...state.active}..remove(key),
      queued: {...state.queued}..remove(key),
      failed: {...state.failed, key},
    );
  }

  Future<void> _markDone(
    DownloadJob job,
    DownloadService service,
    DownloadRepository repository, {
    int? pageCount,
  }) async {
    final key = job.key;
    await repository.save(
      DownloadRecord(
        manga: job.manga,
        chapter: job.chapter,
        pageCount: pageCount ?? job.chapter.pageCount,
        bytes: await service.chapterSize(job.manga, job.chapter),
        downloadedAt: DateTime.now(),
      ),
    );
    state = state.copyWith(
      done: {...state.done, key},
      active: {...state.active}..remove(key),
      queued: {...state.queued}..remove(key),
      failed: {...state.failed}..remove(key),
    );
  }

  Future<void> remove(Manga manga, Chapter chapter) async {
    final key = keyOf(manga, chapter);
    // Un chapitre en cours ne peut pas être supprimé proprement sans annuler
    // sa requête HTTP : on l'ignore, l'interface propose « Arrêter » pour les
    // chapitres actifs.
    if (state.active.containsKey(key)) return;
    _queue.removeWhere((job) => job.key == key);
    _renumberQueue();
    if (_queue.isNotEmpty) {
      await ref.read(downloadQueueRepositoryProvider).addAll(_queue);
    }
    await ref.read(downloadServiceProvider).deleteChapter(manga, chapter);
    await ref.read(downloadRepositoryProvider).remove(key);
    await ref.read(downloadQueueRepositoryProvider).remove(key);
    state = state.copyWith(
      done: {...state.done}..remove(key),
      queued: {...state.queued}..remove(key),
      failed: {...state.failed}..remove(key),
    );
    if (_queue.isEmpty && !_running) {
      unawaited(
        BackgroundDownloads.stop(shouldStop: () => _queue.isEmpty && !_running),
      );
    }
  }

  /// Supprime tous les fichiers et tout l'index des téléchargements.
  Future<void> clearAll() async {
    _generation++;
    _queue.clear();
    _stoppedKeys.clear();
    _activeToken?.cancel('Tout supprimer');
    _wakeLoop();
    state = DownloadsState(paused: state.paused);
    await ref.read(downloadServiceProvider).clearAll();
    await ref.read(downloadRepositoryProvider).clear();
    await ref.read(downloadQueueRepositoryProvider).clear();
    unawaited(
      BackgroundDownloads.stop(shouldStop: () => _queue.isEmpty && !_running),
    );
  }
}

final downloadsProvider = NotifierProvider<DownloadsNotifier, DownloadsState>(
  DownloadsNotifier.new,
);
