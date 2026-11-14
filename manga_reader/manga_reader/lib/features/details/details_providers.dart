import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/models/chapter.dart';
import '../../data/models/manga.dart';

class DetailsData {
  const DetailsData(this.manga, this.chapters);

  final Manga manga;

  /// Chapitres du plus ancien au plus récent.
  final List<Chapter> chapters;
}

/// Charge les infos complètes d'un manga + sa liste de chapitres.
final mangaDetailsProvider = FutureProvider.autoDispose
    .family<DetailsData, Manga>((ref, manga) async {
      final source = ref.watch(sourceByIdProvider(manga.sourceId));
      if (source == null) {
        throw StateError('Source introuvable : ${manga.sourceId}');
      }
      // Recharge automatiquement si la langue des chapitres change.
      ref.watch(settingsProvider.select((s) => s.contentLanguage));

      final full = await source.fetchMangaDetails(manga);
      final chapters = await source.fetchChapters(full);

      // Si le manga est dans la bibliothèque, on met à jour ses infos et son compteur de chapitres.
      await ref.read(libraryRepositoryProvider).syncIfInLibrary(full, [
        for (final c in chapters) c.id,
      ]);

      return DetailsData(full, chapters);
    });
