// Sonde de diagnostic (temporaire).
import 'package:dio/dio.dart';
import 'package:manga_reader/core/constants.dart';
import 'package:manga_reader/data/models/manga.dart';
import 'package:manga_reader/data/sources/madara_source.dart';
import 'package:manga_reader/data/sources/manga_source.dart';
import 'package:manga_reader/data/sources/sushiscan_source.dart';

const browserHeaders = {
  'User-Agent':
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/122.0 Mobile Safari/537.36',
  'Accept':
      'text/html,application/xhtml+xml,application/xml;q=0.9,'
      'image/avif,image/webp,*/*;q=0.8',
  'Accept-Language': 'fr-FR,fr;q=0.9,en;q=0.8',
  'Upgrade-Insecure-Requests': '1',
  'Sec-Fetch-Dest': 'document',
  'Sec-Fetch-Mode': 'navigate',
  'Sec-Fetch-Site': 'none',
  'Sec-Fetch-User': '?1',
};

Future<void> main(List<String> args) async {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'User-Agent': AppConstants.userAgent},
    ),
  );

  if (args.isNotEmpty && args.first == 'get') {
    final url = args[1];
    final full = args.length > 2 && args[2] == 'full';
    print('GET $url (headers=${full ? 'browser' : 'ua seul'})');
    try {
      final res = await dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          headers: full
              ? browserHeaders
              : {'User-Agent': browserHeaders['User-Agent']},
        ),
      );
      final body = res.data ?? '';
      print('  -> ${res.statusCode} realUri=${res.realUri} ${body.length} car.');
      final marker = body.contains('Just a moment')
          ? 'CHALLENGE'
          : body.contains('ori-card')
          ? 'ori-card OK'
          : body.contains('wp-manga')
          ? 'madara OK'
          : 'inconnu';
      print('  marqueur: $marker');
      print('  debut: ${body.substring(0, body.length < 200 ? body.length : 200)}');
    } on DioException catch (e) {
      print('  -> ERR ${e.response?.statusCode} ${e.type}');
      final body = '${e.response?.data ?? ''}';
      if (body.isNotEmpty) {
        print('  corps: ${body.substring(0, body.length < 300 ? body.length : 300)}');
      }
    }
    return;
  }

  final source = args.isNotEmpty && args.first == 'sushi'
      ? SushiscanSource(dio)
      : MangasOriginesSource(dio);
  print('== ${source.name} ==');
  try {
    final page1 = await source.fetchCatalog(
      page: 1,
      query: const CatalogQuery(),
    );
    print('catalog p1 : ${page1.mangas.length} mangas, next=${page1.hasNextPage}');
    for (final m in page1.mangas.take(3)) {
      print('  - ${m.title} | ${m.coverUrl}');
    }
    final search = await source.fetchCatalog(
      page: 1,
      query: const CatalogQuery(text: 'one piece'),
    );
    print('search "one piece" : ${search.mangas.length} mangas');
    if (page1.mangas.isNotEmpty) {
      final target = page1.mangas.first;
      final details = await source.fetchMangaDetails(target);
      print(
        'details : ${details.title} | statut=${details.status.label} | '
        'genres=${details.genres} | auteur=${details.author} | '
        'desc=${details.description.length} car. | cover=${details.coverUrl}',
      );
      final chapters = await source.fetchChapters(details);
      print('chapitres : ${chapters.length}');
      if (chapters.isNotEmpty) {
        final last = chapters.last;
        print('  dernier : ${last.displayTitle} | ${last.id}');
        final pages = await source.fetchPages(last);
        print('pages : ${pages.length}');
        if (pages.isNotEmpty) print('  page 1 : ${pages.first.imageUrl}');
      }
    }
  } catch (e, stack) {
    print('ERREUR : $e');
    print(stack.toString().split('\n').take(6).join('\n'));
  }
}
