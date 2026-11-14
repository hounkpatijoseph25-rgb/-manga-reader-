import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// Résultat d'une mise à jour de la bibliothèque.
class LibraryUpdateReport {
  const LibraryUpdateReport({
    required this.checked,
    required this.failed,
    required this.newChapters,
    required this.titles,
  });

  static const empty = LibraryUpdateReport(
    checked: 0,
    failed: 0,
    newChapters: 0,
    titles: <String>[],
  );

  /// Mangas dont les chapitres ont pu être relus.
  final int checked;

  /// Mangas injoignables (hors connexion, source retirée…).
  final int failed;

  /// Nombre de nouveaux chapitres détectés.
  final int newChapters;

  /// Titres des mangas qui ont gagné des chapitres.
  final List<String> titles;
}

class LibraryUpdateState {
  const LibraryUpdateState({this.running = false, this.report});

  final bool running;
  final LibraryUpdateReport? report;
}

/// Mise à jour automatique de la bibliothèque.
///
/// Au lancement (et à la demande), l'application relit la liste des chapitres
/// de chaque manga suivi : les nouveaux chapitres sont enregistrés, les
/// compteurs de la bibliothèque sont corrigés et les couvertures sont mises de
/// côté pour rester visibles hors connexion.
class LibraryUpdater extends Notifier<LibraryUpdateState> {
  Future<LibraryUpdateReport>? _inflight;

  @override
  LibraryUpdateState build() {
    // Lancement en arrière-plan : l'interface n'attend jamais après ça.
    Future<void>.microtask(refresh);
    return const LibraryUpdateState();
  }

  /// Une seule vérification à la fois : les appels simultanés (lancement,
  /// tâche de fond, bouton) partagent la même exécution.
  Future<LibraryUpdateReport> refresh() {
    final current = _inflight;
    if (current != null) return current;
    final future = _run();
    _inflight = future;
    return future.whenComplete(() => _inflight = null);
  }

  Future<LibraryUpdateReport> _run() async {
    state = LibraryUpdateState(running: true, report: state.report);

    final entries = ref.read(libraryRepositoryProvider).all();
    final repository = ref.read(libraryRepositoryProvider);
    final chapterCache = ref.read(chapterCacheRepositoryProvider);
    final covers = ref.read(coverIndexProvider.notifier);
    final updates = ref.read(updatesRepositoryProvider);

    var checked = 0;
    var failed = 0;
    var added = 0;
    final titles = <String>[];

    for (final entry in entries) {
      final source = ref.read(sourceByIdProvider(entry.manga.sourceId));
      if (source == null) continue;
      try {
        final full = await source.fetchMangaDetails(entry.manga);
        final chapters = await source.fetchChapters(full);
        if (chapters.isNotEmpty) {
          final ids = [for (final c in chapters) c.id];
          final known = repository.chapterIds(entry.manga.key).toSet();
          final freshIds = ids.where((id) => !known.contains(id)).toList();
          // Une bibliothèque vide de références (premier passage) ne doit pas
          // être signalée comme « tout est nouveau ».
          if (known.isNotEmpty && freshIds.isNotEmpty) {
            added += freshIds.length;
            titles.add(full.title);
            await updates.add(entry.manga.key, freshIds);
          }
          await repository.syncIfInLibrary(full, ids);
          await chapterCache.save(full.key, chapters);
        }
        final cover = full.coverUrl;
        if (cover != null && cover.startsWith('http')) {
          await covers.ensure(cover);
        }
        checked++;
      } catch (_) {
        failed++;
      }
      // On laisse respirer le réseau et l'interface entre deux mangas.
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }

    await updates.markRun(DateTime.now());
    final report = LibraryUpdateReport(
      checked: checked,
      failed: failed,
      newChapters: added,
      titles: titles,
    );
    state = LibraryUpdateState(report: report);
    return report;
  }
}

final libraryUpdaterProvider =
    NotifierProvider<LibraryUpdater, LibraryUpdateState>(LibraryUpdater.new);
