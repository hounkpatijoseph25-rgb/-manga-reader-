// Sonde d'audit des sources (outil temporaire, pas un test).
// Utilise dio + les VRAIES classes sources, donc reproduit exactement le
// comportement de l'app (TLS Dart, en-têtes, parsing).
import 'package:dio/dio.dart';
import 'package:manga_reader/data/models/chapter.dart';
import 'package:manga_reader/data/sources/fmteam_source.dart';
import 'package:manga_reader/data/sources/lelscan_source.dart';
import 'package:manga_reader/data/sources/manga_source.dart';
import 'package:manga_reader/data/sources/mangadex_source.dart';
import 'package:manga_reader/data/sources/poseidon_scans_source.dart';
import 'package:manga_reader/data/sources/scan_vf_source.dart';
import 'package:manga_reader/data/sources/sushiscan_source.dart';

Future<void> main(List<String> args) async {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 45),
    ),
  );

  final only = args.isNotEmpty ? args.first : null;
  final sources = <MangaSource>[
    MangaDexSource(dio, language: () => 'fr', dataSaver: () => false),
    FmteamSource(dio),
    SushiscanSource(dio),
    ScanVfSource(dio),
    LelscanSource(dio),
    PoseidonScansSource(dio),
    MangaDexSource(
      dio,
      language: () => 'fr',
      dataSaver: () => false,
      id: 'mangadex18',
      name: 'MangaDex 18+',
      adult: true,
      ratings: const ['erotica', 'pornographic'],
    ),
  ];

  final summary = <String>[];
  for (final s in sources) {
    if (only != null && s.id != only) continue;
    print('\n===== ${s.name}  (${s.id}) =====');
    var cat = -1;
    var search = -1;
    var chapters = -1;
    var pages = -1;
    var details = '-';
    try {
      final p1 = await s.fetchCatalog(page: 1, query: const CatalogQuery());
      cat = p1.mangas.length;
      print('catalogue p1 : $cat  next=${p1.hasNextPage}');
      if (p1.mangas.isNotEmpty) print('  1er : ${p1.mangas.first.title}');
    } catch (e) {
      print('catalogue ERR : $e');
    }
    try {
      final r = await s.fetchCatalog(
        page: 1,
        query: const CatalogQuery(text: 'one piece'),
      );
      search = r.mangas.length;
      print('recherche "one piece" : $search');
    } catch (e) {
      print('recherche ERR : $e');
    }
    try {
      final p1 = await s.fetchCatalog(page: 1, query: const CatalogQuery());
      if (p1.mangas.isNotEmpty) {
        final d = await s.fetchMangaDetails(p1.mangas.first);
        details =
            '${d.title} | desc=${d.description.length}c | genres=${d.genres.length}';
        print('details : $details');
        final chs = await s.fetchChapters(d);
        chapters = chs.length;
        print('chapitres : $chapters');
        if (chs.isNotEmpty) {
          final candidates = <Chapter>[
            chs.last,
            chs.first,
            chs[chs.length ~/ 2],
          ];
          final tried = <String>{};
          for (final c in candidates) {
            if (!tried.add(c.id)) continue;
            try {
              final ps = await s.fetchPages(c);
              pages = ps.length;
              print('pages (ch. ${c.number}) : $pages');
              if (ps.isNotEmpty) print('  img1 : ${ps.first.imageUrl}');
              break;
            } catch (e) {
              print('  pages ERR (ch. ${c.number}) : $e');
            }
          }
        }
      }
    } catch (e) {
      print('details/chapitres/pages ERR : $e');
    }
    summary.add(
      '${s.name.padRight(18)} cat=$cat search=$search '
      'chapitres=$chapters pages=$pages | $details',
    );
  }

  print('\n========== RESUME ==========');
  for (final l in summary) {
    print(l);
  }
}
