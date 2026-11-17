import '../models/chapter.dart';
import '../models/download_record.dart';
import '../models/manga.dart';
import '../models/manga_page.dart';
import 'manga_source.dart';

/// Chapitres téléchargés depuis l'application, lisibles hors connexion.
///
/// Les identifiants sont réécrits : le manga garde la clé d'origine
/// (`source:id`) comme `id` pour retrouver ses enregistrements, mais sa
/// `sourceId` devient `downloads` pour que la fiche et le lecteur s'appuient sur
/// cette source (et non sur le site d'origine, qui exige une connexion).
class DownloadsSource extends MangaSource {
  DownloadsSource({required this.records, required this.chapterPages});

  /// Enregistrements des chapitres téléchargés (manga, chapitre, pages, taille).
  final List<DownloadRecord> Function() records;

  /// Images locales d'un chapitre d'origine (dossier `downloads/`).
  final Future<List<String>?> Function(Manga manga, Chapter chapter)
  chapterPages;

  @override
  String get id => 'downloads';

  @override
  String get name => 'Téléchargements';

  @override
  String get description {
    final count = _mangas().length;
    if (count == 0) return 'Aucun chapitre téléchargé';
    return '$count manga(s) lisible(s) hors connexion';
  }

  Map<String, Manga> _mangas() {
    final result = <String, Manga>{};
    for (final record in records()) {
      final key = record.manga.key;
      result.putIfAbsent(
        key,
        () => Manga(
          id: key,
          sourceId: id,
          title: record.manga.title,
          coverUrl: record.manga.coverUrl,
          author: record.manga.author,
          artist: record.manga.artist,
          description: record.manga.description,
          status: record.manga.status,
          genres: record.manga.genres,
        ),
      );
    }
    return result;
  }

  List<DownloadRecord> _recordsOf(String mangaId) => [
    for (final record in records())
      if (record.manga.key == mangaId) record,
  ];

  @override
  Future<MangaPageResult> fetchCatalog({
    required int page,
    required CatalogQuery query,
  }) async {
    final text = query.text.trim().toLowerCase();
    final mangas = [
      for (final manga in _mangas().values)
        if (text.isEmpty || manga.title.toLowerCase().contains(text)) manga,
    ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    const pageSize = 20;
    final start = (page - 1) * pageSize;
    if (start >= mangas.length) return const MangaPageResult([], false);
    final end = (start + pageSize).clamp(0, mangas.length);
    return MangaPageResult(mangas.sublist(start, end), end < mangas.length);
  }

  @override
  Future<Manga> fetchMangaDetails(Manga manga) async =>
      _mangas()[manga.id] ?? manga;

  @override
  Future<List<Chapter>> fetchChapters(Manga manga) async {
    final found = _recordsOf(manga.id)
      ..sort((a, b) => a.chapter.numberValue.compareTo(b.chapter.numberValue));
    return [
      for (final record in found)
        Chapter(
          id: record.chapter.id,
          mangaId: manga.id,
          sourceId: id,
          number: record.chapter.number,
          title: record.chapter.title,
          volume: record.chapter.volume,
          publishedAt: record.chapter.publishedAt,
          pageCount: record.pageCount,
          scanlator: record.chapter.scanlator,
        ),
    ];
  }

  @override
  Future<List<MangaPage>> fetchPages(Chapter chapter) async {
    for (final record in records()) {
      if (record.manga.key != chapter.mangaId) continue;
      if (record.chapter.id != chapter.id) continue;
      final paths = await chapterPages(record.manga, record.chapter);
      if (paths == null || paths.isEmpty) continue;
      return [
        for (var i = 0; i < paths.length; i++)
          MangaPage(
            index: i,
            imageUrl: '',
            localPath: paths[i],
            cacheKey: paths[i],
          ),
      ];
    }
    return const [];
  }

  @override
  Future<List<Genre>> fetchGenres() async => const [];
}
