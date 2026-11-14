import '../models/chapter.dart';
import '../models/manga.dart';
import '../models/manga_page.dart';
import 'manga_source.dart';

/// Source de démonstration (données fictives + images aléatoires de picsum.photos).
/// Pratique pour tester tous les écrans, et c'est un bon exemple minimal
/// pour écrire ta propre source.
class DemoSource implements MangaSource {
  DemoSource();

  static const _pageSize = 12;
  static const _genreNames = ['Action', 'Aventure', 'Comédie'];

  late final List<Manga> _all = List.generate(
    40,
    (i) => Manga(
      id: '$i',
      sourceId: id,
      title: 'Manga démo ${i + 1}',
      coverUrl: 'https://picsum.photos/seed/demo$i/300/450',
      author: 'Auteur ${i % 5 + 1}',
      description:
          "Série fictive n°${i + 1}, créée pour tester les écrans de l'application. "
          'Elle contient 12 chapitres de 8 pages chacun, remplis d\'images aléatoires. '
          'Utilise-la pour essayer les modes de lecture, la bibliothèque et les téléchargements.',
      status: i % 3 == 0 ? MangaStatus.completed : MangaStatus.ongoing,
      genres: [_genreNames[i % 3], _genreNames[(i + 1) % 3]],
    ),
  );

  @override
  String get id => 'demo';

  @override
  String get name => 'Démo (données fictives)';

  @override
  String get description =>
      'Pour tester l\'application sans connexion à un vrai catalogue';

  @override
  Future<MangaPageResult> fetchCatalog({
    required int page,
    required CatalogQuery query,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final text = query.text.trim().toLowerCase();
    var items = _all.where((m) {
      final okText = text.isEmpty || m.title.toLowerCase().contains(text);
      final okGenres = query.genreIds.every(m.genres.contains);
      return okText && okGenres;
    }).toList();
    switch (query.sort) {
      case CatalogSort.popularity:
        break;
      case CatalogSort.latest:
        items = items.reversed.toList();
      case CatalogSort.title:
        items.sort((a, b) => a.title.compareTo(b.title));
    }
    final start = (page - 1) * _pageSize;
    if (start >= items.length) return const MangaPageResult([], false);
    final end = start + _pageSize > items.length
        ? items.length
        : start + _pageSize;
    return MangaPageResult(items.sublist(start, end), end < items.length);
  }

  @override
  Future<Manga> fetchMangaDetails(Manga manga) async => manga;

  @override
  Future<List<Chapter>> fetchChapters(Manga manga) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return [
      for (var n = 1; n <= 12; n++)
        Chapter(
          id: '${manga.id}-c$n',
          mangaId: manga.id,
          sourceId: id,
          number: '$n',
          title: 'Chapitre de démonstration',
          publishedAt: DateTime(2025, 1, 1).add(Duration(days: n * 7)),
          pageCount: 8,
        ),
    ];
  }

  @override
  Future<List<MangaPage>> fetchPages(Chapter chapter) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return [
      for (var i = 0; i < 8; i++)
        MangaPage(
          index: i,
          imageUrl: 'https://picsum.photos/seed/${chapter.id}-$i/800/1200',
          cacheKey: 'demo/${chapter.id}/$i',
        ),
    ];
  }

  @override
  Future<List<Genre>> fetchGenres() async => [
    for (final g in _genreNames) Genre(id: g, name: g),
  ];
}
