import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/models/chapter.dart';
import '../../data/models/manga.dart';

class DetailsData {
  const DetailsData(this.manga, this.chapters, {this.offline = false});

  final Manga manga;

  /// Chapitres du plus ancien au plus récent.
  final List<Chapter> chapters;

  /// Vrai quand la liste vient du cache local (aucun réseau disponible).
  final bool offline;
}

/// Charge les infos complètes d'un manga + sa liste de chapitres.
///
/// La liste obtenue est mise en cache : si le réseau est indisponible, on
/// retombe sur ce cache pour pouvoir malgré tout ouvrir la fiche et relire les
/// chapitres téléchargés.
final mangaDetailsProvider = FutureProvider.autoDispose
    .family<DetailsData, Manga>((ref, manga) async {
      final source = ref.watch(sourceByIdProvider(manga.sourceId));
      if (source == null) {
        throw StateError('Source introuvable : ${manga.sourceId}');
      }
      // Recharge automatiquement si la langue des chapitres change.
      ref.watch(settingsProvider.select((s) => s.contentLanguage));

      final cache = ref.read(chapterCacheRepositoryProvider);

      try {
        final full = await source.fetchMangaDetails(manga);
        final chapters = await source.fetchChapters(full);
        await cache.save(manga.key, chapters);

        // Si le manga est dans la bibliothèque, on met à jour ses infos et son compteur de chapitres.
        await ref.read(libraryRepositoryProvider).syncIfInLibrary(full, [
          for (final c in chapters) c.id,
        ]);

        return DetailsData(full, chapters);
      } catch (error) {
        final cached = cache.load(manga.key);
        if (cached.isEmpty) rethrow;
        return DetailsData(manga, cached, offline: true);
      }
    });
