import 'package:dio/dio.dart';

import '../models/chapter.dart';
import '../models/manga.dart';
import '../models/manga_page.dart';
import 'manga_source.dart';
import 'scrape_utils.dart';

/// Source « Lelscan » (https://lelscan.net).
///
/// Pages série `/lecture-en-ligne-<slug>` (parfois `.php`), chapitres
/// `/scan-<slug>/<num>`, lecteur paginé `/scan-<slug>/<num>/<page>`.
/// Les images suivent `/mangas/<slug>/<num>/<page>.jpg`.
class LelscanSource extends MangaSource {
  LelscanSource(this._dio);

  final Dio _dio;

  static const _base = 'https://lelscan.net';

  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/122.0 Mobile Safari/537.36';

  @override
  String get id => 'lelscan';

  @override
  String get name => 'Lelscan';

  @override
  String get description =>
      'Scans FR — classiques et nouveautés de lelscan.net';

  // ---------------------------------------------------------------- catalogue

  @override
  Future<MangaPageResult> fetchCatalog({
    required int page,
    required CatalogQuery query,
  }) async {
    // Le site n'a ni pagination ni recherche : la page d'accueil liste les
    // séries populaires (une seule page).
    if (page > 1) return const MangaPageResult([], false);
    final html = await _get('$_base/');
    final mangas = _parseHome(html);
    final text = query.text.trim().toLowerCase();
    if (text.isEmpty) return MangaPageResult(mangas, false);
    return MangaPageResult(
      mangas
          .where((m) => m.title.toLowerCase().contains(text))
          .toList(),
      false,
    );
  }

  List<Manga> _parseHome(String html) {
    final result = <Manga>[];
    final seen = <String>{};
    final matches = RegExp(
      r'href="https://lelscan\.net/lecture-en-ligne-([a-z0-9\-]+)(?:\.php)?"',
    ).allMatches(html);
    for (final match in matches) {
      final slug = match[1]!;
      if (!seen.add(slug)) continue;
      result.add(
        Manga(
          id: slug,
          sourceId: id,
          title: _label(slug),
          coverUrl: '$_base/mangas/$slug/thumb_cover.jpg',
        ),
      );
    }
    return result;
  }

  // ------------------------------------------------------------------ détails

  @override
  Future<Manga> fetchMangaDetails(Manga manga) async {
    final html = await _detailHtml(manga.id);
    final h1 = cleanText(
      firstGroup(html, r'<h1[^>]*>(.*?)</h1>') ?? '',
    );
    final title = h1
        .replaceFirst(RegExp(r'^Lecture en ligne\s+', caseSensitive: false), '')
        .replaceFirst(RegExp(r'\s+scan\s*$', caseSensitive: false), '')
        .trim();
    final description = firstGroup(
      html,
      r'<meta name="description" content="([^"]*)"',
    );
    final cover = firstGroup(
      html,
      r'<img[^>]+src="(/mangas/[^"]*thumb_cover\.jpg)"',
    );

    return Manga(
      id: manga.id,
      sourceId: manga.sourceId,
      title: title.isEmpty ? manga.title : title,
      coverUrl: cover == null
          ? manga.coverUrl
          : '$_base${decodeHtmlEntities(cover)}',
      description: description == null
          ? manga.description
          : cleanText(decodeHtmlEntities(description)),
      status: manga.status,
    );
  }

  Future<String> _detailHtml(String slug) async {
    try {
      return await _get('$_base/lecture-en-ligne-$slug');
    } on StateError {
      return _get('$_base/lecture-en-ligne-$slug.php');
    }
  }

  // ---------------------------------------------------------------- chapitres

  @override
  Future<List<Chapter>> fetchChapters(Manga manga) async {
    final html = await _detailHtml(manga.id);
    final chapters = <Chapter>[];
    final seen = <String>{};
    final matches = RegExp(
      r'href="(https://lelscan\.net/scan-' +
          RegExp.escape(manga.id) +
          r'/(\d+(?:[.,]\d+)?))"',
    ).allMatches(html);
    for (final match in matches) {
      final url = match[1]!;
      final number = match[2]!.replaceAll(',', '.');
      if (!seen.add(number)) continue;
      chapters.add(
        Chapter(
          id: url,
          mangaId: manga.id,
          sourceId: id,
          number: number,
        ),
      );
    }
    chapters.sort((a, b) => a.numberValue.compareTo(b.numberValue));
    return chapters;
  }

  @override
  Future<List<MangaPage>> fetchPages(Chapter chapter) async {
    final segments = Uri.parse(chapter.id).pathSegments;
    if (segments.length < 2) {
      throw StateError('Chapitre Lelscan illisible.');
    }
    final slug = segments[0].replaceFirst('scan-', '');
    final number = segments[1];

    // La première page contient la liste déroulante des pages du chapitre.
    final html = await _get('${chapter.id}/1');
    var pages = 1;
    for (final match in RegExp(r'<option value="[^"]*/(\d+)"').allMatches(
      html,
    )) {
      final value = int.tryParse(match[1]!);
      if (value != null && value > pages) pages = value;
    }

    final urls = [
      for (var i = 0; i < pages; i++)
        '$_base/mangas/$slug/$number/${i.toString().padLeft(2, '0')}.jpg',
    ];
    return [
      for (var i = 0; i < urls.length; i++)
        MangaPage(
          index: i,
          imageUrl: urls[i],
          cacheKey: Uri.parse(urls[i]).path,
        ),
    ];
  }

  // ------------------------------------------------------------------ genres

  @override
  Future<List<Genre>> fetchGenres() async => const [];

  // ------------------------------------------------------------------- outils

  Future<String> _get(String url) async {
    try {
      final res = await _dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'User-Agent': _userAgent,
            'Accept-Language': 'fr-FR,fr;q=0.9',
          },
        ),
      );
      return res.data ?? '';
    } on DioException {
      throw StateError('Lelscan est injoignable pour le moment.');
    }
  }

  static String _label(String slug) {
    final words = slug
        .split('-')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
    return words.isEmpty ? slug : words;
  }
}
