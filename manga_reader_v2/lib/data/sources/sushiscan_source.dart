import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/chapter.dart';
import '../models/manga.dart';
import '../models/manga_page.dart';
import 'manga_source.dart';
import 'scrape_utils.dart';

/// Source « Sushiscan » (https://sushiscan.net).
///
/// Thème Mangastream : catalogue `/catalogue/?page=N&order=update`, séries
/// `/catalogue/<slug>/`, chapitres `/…-chapitre-<n>/`. Les images sont
/// injectées en JSON par le lecteur (`ts_reader.run({...})`).
class SushiscanSource extends MangaSource {
  SushiscanSource(this._dio);

  final Dio _dio;

  static const _base = 'https://sushiscan.net';

  /// Le site attend un navigateur mobile : il redirige les autres agents.
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/122.0 Mobile Safari/537.36';

  List<Genre>? _genres;

  @override
  String get id => 'sushiscan';

  @override
  String get name => 'Sushiscan';

  @override
  String get description =>
      'Scans FR — mangas, manhwas et webtoons de sushiscan.net';

  // ---------------------------------------------------------------- catalogue

  @override
  Future<MangaPageResult> fetchCatalog({
    required int page,
    required CatalogQuery query,
  }) async {
    final text = query.text.trim();
    final String url;
    var paginated = false;

    if (text.isNotEmpty) {
      url = '$_base/?s=${Uri.encodeQueryComponent(text)}';
    } else if (query.genreIds.isNotEmpty) {
      url = '$_base/genres/${query.genreIds.first}/';
    } else {
      // Les paramètres de tri du site ne sont pas fiables : on garde l'ordre
      // « dernières mises à jour ».
      url = '$_base/catalogue/?page=$page&order=update';
      paginated = true;
    }

    final html = await _get(url);
    final mangas = _parseCards(html);
    if (mangas.isEmpty) return const MangaPageResult([], false);
    return MangaPageResult(mangas, paginated && mangas.length >= 15);
  }

  List<Manga> _parseCards(String html) {
    final result = <Manga>[];
    final chunks = html.split('<div class="bsx">');
    for (final chunk in chunks.skip(1)) {
      final block = _until(chunk, '</div></div></div>');
      final href = firstGroup(block, r'href="([^"]+)"');
      if (href == null || !href.contains('/catalogue/')) continue;
      final slug = segmentAfter(href, 'catalogue');
      final title = cleanText(
        firstGroup(block, r'class="tt">\s*([^<]+)<') ??
            firstGroup(block, r'title="([^"]*)"') ??
            '',
      );
      if (slug.isEmpty || title.isEmpty) continue;

      final cover = firstGroup(block, r'<img[^>]+src="([^"]+)"');
      result.add(
        Manga(
          id: slug,
          sourceId: id,
          title: title,
          coverUrl: cover == null ? null : decodeHtmlEntities(cover),
        ),
      );
    }
    return result;
  }

  // ------------------------------------------------------------------ détails

  @override
  Future<Manga> fetchMangaDetails(Manga manga) async {
    final html = await _get('$_base/catalogue/${manga.id}/');
    final title = cleanText(
      firstGroup(html, r'entry-title"[^>]*>([^<]*)') ?? '',
    );
    final cover = firstGroup(
      html,
      r'<div class="thumb"[^>]*>\s*<img[^>]+src="([^"]+)"',
    );
    final description = firstGroup(
      html,
      r'itemprop="description"[^>]*>(.*?)</div>',
    );
    final info = _infoTable(html);
    final genres = _genresFromPage(html, info);

    return Manga(
      id: manga.id,
      sourceId: manga.sourceId,
      title: title.isEmpty ? manga.title : title,
      coverUrl: cover == null ? manga.coverUrl : decodeHtmlEntities(cover),
      author: info['auteur'] ?? manga.author,
      artist: info['dessinateur'] ?? manga.artist,
      description: description == null
          ? manga.description
          : stripHtml(description),
      status: info['statut'] == null ? manga.status : _status(info['statut']!),
      genres: genres.isEmpty ? manga.genres : genres,
    );
  }

  /// Tableau « Statut / Type / Année / Auteur / Dessinateur / … ».
  Map<String, String> _infoTable(String html) {
    final result = <String, String>{};
    final rows = RegExp(
      r'<tr>\s*<td>([^<]*)</td>\s*<td>(.*?)</td>\s*</tr>',
      dotAll: true,
    ).allMatches(html);
    for (final row in rows) {
      final key = cleanText(row[1] ?? '').toLowerCase();
      final value = cleanText(stripHtml(row[2] ?? ''));
      if (key.isEmpty || value.isEmpty) continue;
      result.putIfAbsent(key, () => value);
    }
    return result;
  }

  List<String> _genresFromPage(String html, Map<String, String> info) {
    final block = firstGroup(html, r'class="seriestugenre"[^>]*>(.*?)</div>');
    if (block != null) {
      final names = allGroups(
        block,
        r'<a[^>]*>([^<]*)</a>',
      ).map(cleanText).where((name) => name.isNotEmpty).toList();
      if (names.isNotEmpty) return names;
    }
    final raw = info['genres'] ?? info['genre'] ?? '';
    return raw
        .split(',')
        .map(cleanText)
        .where((name) => name.isNotEmpty)
        .toList();
  }

  // ---------------------------------------------------------------- chapitres

  @override
  Future<List<Chapter>> fetchChapters(Manga manga) async {
    final html = await _get('$_base/catalogue/${manga.id}/');
    final start = html.indexOf('id="chapterlist"');
    if (start < 0) return const [];
    var end = html.indexOf('</ul>', start);
    if (end < 0) end = html.length;
    final block = html.substring(start, end);

    final volumes = <Chapter>[];
    final numbered = <Chapter>[];
    final chunks = block.split('<li data-num="');
    for (final chunk in chunks.skip(1)) {
      final label = cleanText(firstGroup(chunk, r'^([^"]*)') ?? '');
      final href = firstGroup(chunk, r'<a[^>]*href="([^"]+)"');
      if (href == null) continue;
      final date = firstGroup(chunk, r'chapterdate">([^<]*)') ?? '';

      final isVolume = label.toLowerCase().startsWith('volume');
      final number = isVolume
          ? null
          : RegExp(r'(\d+(?:[.,]\d+)?)')
                .firstMatch(label)
                ?.group(1)
                ?.replaceAll(',', '.');
      final volume = isVolume ? _firstNumber(label) : null;

      final chapter = Chapter(
        id: decodeHtmlEntities(href),
        mangaId: manga.id,
        sourceId: id,
        number: number,
        volume: volume,
        title: '',
        publishedAt: parseFrenchDate(date),
      );
      if (number == null && volume != null) {
        volumes.add(chapter);
      } else {
        numbered.add(chapter);
      }
    }

    numbered.sort((a, b) => a.numberValue.compareTo(b.numberValue));
    return [...volumes, ...numbered];
  }

  @override
  Future<List<MangaPage>> fetchPages(Chapter chapter) async {
    final html = await _get(chapter.id);
    final urls = _extractImages(html);
    if (urls.isEmpty) {
      throw StateError('Aucune page trouvée pour ce chapitre.');
    }
    return [
      for (var i = 0; i < urls.length; i++)
        MangaPage(
          index: i,
          imageUrl: urls[i],
          cacheKey: Uri.parse(urls[i]).path,
        ),
    ];
  }

  List<String> _extractImages(String html) {
    final marker = html.indexOf('ts_reader.run(');
    if (marker >= 0) {
      final start = html.indexOf('{', marker);
      final end = start < 0 ? -1 : _matchingBrace(html, start);
      if (end > start) {
        try {
          final data = jsonDecode(html.substring(start, end + 1));
          final sources = data is Map ? data['sources'] : null;
          if (sources is List) {
            for (final entry in sources) {
              if (entry is! Map || entry['images'] is! List) continue;
              final images = (entry['images'] as List)
                  .map((url) => '$url')
                  .where((url) => url.isNotEmpty)
                  .toList();
              if (images.isNotEmpty) return images;
            }
          }
        } on FormatException {
          // On retombe sur l'extraction par expression régulière.
        }
      }
    }

    final block = firstGroup(html, r'"images"\s*:\s*\[(.*?)\]');
    if (block == null) return const [];
    return [
      for (final match in RegExp(r'"([^"]+)"').allMatches(block))
        match[1]!.replaceAll(r'\/', '/'),
    ];
  }

  /// Index de l'accolade fermant celle ouverte en [start] (chaînes ignorées).
  int _matchingBrace(String text, int start) {
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < text.length; i++) {
      final char = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == r'\') {
          escaped = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }
      if (char == '"') {
        inString = true;
      } else if (char == '{') {
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  // ------------------------------------------------------------------ genres

  static const _fallbackGenres = [
    Genre(id: 'erotique', name: 'Erotique'),
    Genre(id: 'romance', name: 'Romance'),
    Genre(id: 'school-life', name: 'School-Life'),
    Genre(id: 'action', name: 'Action'),
    Genre(id: 'aventure', name: 'Aventure'),
    Genre(id: 'comedie', name: 'Comédie'),
    Genre(id: 'drame', name: 'Drame'),
    Genre(id: 'fantastique', name: 'Fantastique'),
    Genre(id: 'histoires-courtes', name: 'Histoires courtes'),
    Genre(id: 'mature', name: 'Mature'),
    Genre(id: 'fantasy', name: 'Fantasy'),
    Genre(id: 'nekketsu', name: 'Nekketsu'),
    Genre(id: 'surnaturel', name: 'Surnaturel'),
    Genre(id: 'ecchi', name: 'Ecchi'),
    Genre(id: 'historique', name: 'Historique'),
    Genre(id: 'horreur', name: 'Horreur'),
    Genre(id: 'tragique', name: 'Tragique'),
    Genre(id: 'sport', name: 'Sport'),
    Genre(id: 'shojo-ai', name: 'Shôjo-aï'),
    Genre(id: 'mystere', name: 'Mystère'),
  ];

  @override
  Future<List<Genre>> fetchGenres() async {
    final cached = _genres;
    if (cached != null) return cached;

    List<Genre> genres;
    try {
      final html = await _get('$_base/genres/');
      genres = _parseGenres(html);
    } on StateError {
      genres = const [];
    }
    if (genres.isEmpty) genres = List<Genre>.of(_fallbackGenres);
    genres.sort((a, b) => a.name.compareTo(b.name));
    _genres = genres;
    return genres;
  }

  List<Genre> _parseGenres(String html) {
    final byId = <String, Genre>{};
    final matches = RegExp(
      r'href="[^"]*sushiscan\.net/genres/([^"/]+)/"[^>]*>([^<]*)<',
    ).allMatches(html);
    for (final match in matches) {
      final slug = match[1]!;
      final name = cleanText(match[2] ?? '');
      if (slug.isEmpty) continue;
      if (byId.containsKey(slug) && byId[slug]!.name.isNotEmpty) continue;
      byId[slug] = Genre(id: slug, name: name.isEmpty ? _label(slug) : name);
    }
    return byId.values.toList();
  }

  static String _label(String slug) {
    final words = slug.replaceAll('-', ' ').trim();
    if (words.isEmpty) return slug;
    return words[0].toUpperCase() + words.substring(1);
  }

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
      throw StateError('Sushiscan est injoignable pour le moment.');
    }
  }

  static MangaStatus _status(String value) {
    final text = value.toLowerCase();
    if (text.contains('cours')) return MangaStatus.ongoing;
    if (text.contains('termin') || text.contains('complete')) {
      return MangaStatus.completed;
    }
    if (text.contains('pause')) return MangaStatus.hiatus;
    if (text.contains('abandon')) return MangaStatus.cancelled;
    return MangaStatus.unknown;
  }

  static String? _firstNumber(String value) =>
      RegExp(r'(\d+(?:[.,]\d+)?)')
          .firstMatch(value)
          ?.group(1)
          ?.replaceAll(',', '.');

  /// Partie de [text] avant la première occurrence de [marker].
  static String _until(String text, String marker) {
    final index = text.indexOf(marker);
    return index < 0 ? text : text.substring(0, index);
  }
}
