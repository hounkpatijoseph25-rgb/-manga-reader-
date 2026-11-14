import '../models/chapter.dart';
import '../models/manga.dart';
import '../models/manga_page.dart';

enum CatalogSort { popularity, latest, title }

extension CatalogSortX on CatalogSort {
  String get label => switch (this) {
    CatalogSort.popularity => 'Popularité',
    CatalogSort.latest => 'Dernières mises à jour',
    CatalogSort.title => 'Nom (A-Z)',
  };
}

class Genre {
  const Genre({required this.id, required this.name});

  final String id;
  final String name;
}

/// Recherche + filtres + tri appliqués au catalogue d'une source.
class CatalogQuery {
  const CatalogQuery({
    this.text = '',
    this.sort = CatalogSort.popularity,
    this.genreIds = const {},
  });

  final String text;
  final CatalogSort sort;
  final Set<String> genreIds;

  bool get hasFilters => genreIds.isNotEmpty || sort != CatalogSort.popularity;

  CatalogQuery copyWith({
    String? text,
    CatalogSort? sort,
    Set<String>? genreIds,
  }) {
    return CatalogQuery(
      text: text ?? this.text,
      sort: sort ?? this.sort,
      genreIds: genreIds ?? this.genreIds,
    );
  }
}

class MangaPageResult {
  const MangaPageResult(this.mangas, this.hasNextPage);

  final List<Manga> mangas;
  final bool hasNextPage;
}

/// Une "source" = un site ou une API d'où viennent les mangas.
/// Pour en ajouter une : crée une classe qui implémente [MangaSource],
/// puis ajoute-la dans `sourcesProvider` (lib/core/providers.dart).
abstract class MangaSource {
  String get id;
  String get name;
  String get description;

  /// Icône facultative (sources distantes comme Suwayomi).
  String? get iconUrl => null;

  /// `true` pour les sources réservées aux adultes (masquées par défaut).
  bool get isAdult => false;

  Future<MangaPageResult> fetchCatalog({
    required int page,
    required CatalogQuery query,
  });

  Future<Manga> fetchMangaDetails(Manga manga);

  /// Chapitres triés du plus ancien au plus récent.
  Future<List<Chapter>> fetchChapters(Manga manga);

  Future<List<MangaPage>> fetchPages(Chapter chapter);

  Future<List<Genre>> fetchGenres();
}
