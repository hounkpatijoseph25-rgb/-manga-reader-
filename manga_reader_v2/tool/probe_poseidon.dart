// Sonde temporaire : valide la source Poseidon Scans contre le site réel.
import 'package:dio/dio.dart';
import 'package:manga_reader/data/sources/manga_source.dart';
import 'package:manga_reader/data/sources/poseidon_scans_source.dart';

Future<void> main() async {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      followRedirects: true,
      validateStatus: (_) => true,
    ),
  );
  final source = PoseidonScansSource(dio);

  final popular = await source.fetchCatalog(
    page: 1,
    query: const CatalogQuery(),
  );
  print('POPULAR ${popular.mangas.length} next=${popular.hasNextPage}');
  for (final m in popular.mangas.take(3)) {
    print('  ${m.id} | ${m.title} | ${m.coverUrl}');
  }

  final search = await source.fetchCatalog(
    page: 1,
    query: const CatalogQuery(text: 'one'),
  );
  print('SEARCH one ${search.mangas.length} next=${search.hasNextPage}');
  for (final m in search.mangas.take(3)) {
    print('  ${m.title}');
  }

  final latest = await source.fetchCatalog(
    page: 1,
    query: const CatalogQuery(sort: CatalogSort.latest),
  );
  print('LATEST ${latest.mangas.length} next=${latest.hasNextPage}');
  for (final m in latest.mangas.take(3)) {
    print('  ${m.title}');
  }

  if (popular.mangas.isEmpty) return;
  final target = popular.mangas.first;
  final details = await source.fetchMangaDetails(target);
  print(
    'DETAILS ${details.title} | status=${details.status.name} '
    'author=${details.author} artist=${details.artist} '
    'genres=${details.genres.join(",")}',
  );
  print('  desc=${details.description.substring(0, details.description.length.clamp(0, 120))}');

  final chapters = await source.fetchChapters(details);
  print('CHAPTERS ${chapters.length}');
  for (final c in chapters.take(2)) {
    print('  ${c.number} ${c.title} ${c.publishedAt}');
  }
  if (chapters.isNotEmpty) {
    final first = chapters.first;
    final pages = await source.fetchPages(first);
    print('PAGES ch${first.number} -> ${pages.length}');
    print('  ${pages.first.imageUrl}');
  }
}
