import 'package:dio/dio.dart';

import '../models/chapter.dart';
import '../models/manga.dart';
import '../models/manga_page.dart';
import 'manga_source.dart';
import 'scrape_utils.dart';

/// Source du site français **FMTeam** (https://fmteam.fr).
///
/// - catalogue  : `/mangas` (cartes `.manga-row`, `onclick="/manga/<slug>"`)
/// - recherche  : `/mangas?q=<texte>`
/// - fiche      : `/manga/<slug>` (`.chapter-item` → `/read/<slug>/<lang>/ch/<n>`)
/// - lecture    : `/read/<slug>/<lang>/ch/<n>` (images `/storage/comics/...`)
class FmteamSource extends MangaSource {
  FmteamSource(this._dio);

  final Dio _dio;

  static const _base = 'https://fmteam.fr';
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/122.0 Mobile Safari/537.36';

  @override
  String get id => 'fmteam';

  @override
  String get name => 'FMTeam';

  @override
  String get description => 'Scans français (traductions FR de FMTeam)';

  // ---------------------------------------------------------------- catalogue

  @override
  Future<MangaPageResult> fetchCatalog({
    required int page,
    required CatalogQuery query,
  }) async {
    final text = query.text.trim();
    final url = text.isEmpty
        ? '$_base/mangas?page=$page'
        : '$_base/mangas?q=${Uri.encodeQueryComponent(text)}';
    final html = await _get(url);
    final mangas = _parseCards(html);
    final hasNext = html.contains('page=${page + 1}') ||
        html.contains('/mangas?page=${page + 1}');
    return MangaPageResult(mangas, hasNext);
  }

  List<Manga> _parseCards(String html) {
    final result = <Manga>[];
    final seen = <String>{};
    final parts = html.split("onclick=\"window.location='/manga/");
    for (final part in parts.skip(1)) {
      final quote = part.indexOf("'");
      if (quote <= 0) continue;
      final slug = part.substring(0, quote).split('?').first;
      if (slug.isEmpty || !seen.add(slug)) continue;
      final block = part.length > 2500 ? part.substring(0, 2500) : part;
      final name = cleanText(
        firstGroup(block, r'manga-row-name[^>]*>([^<]*)') ?? '',
      );
      final cover = firstGroup(block, r'manga-row-cover[^>]+src="([^"]+)"');
      final author = firstGroup(block, r'manga-row-author[^>]*>\s*([^<]*)');
      result.add(
        Manga(
          id: slug,
          sourceId: id,
          title: name.isEmpty ? _prettySlug(slug) : name,
          coverUrl: cover == null
              ? null
              : absoluteUrl(_base, decodeHtmlEntities(cover)),
          author: author == null
              ? null
              : cleanText(author.replaceFirst(RegExp(r'^Auteur\s*:\s*'), '')),
        ),
      );
    }
    return result;
  }

  // ------------------------------------------------------------------ détails

  @override
  Future<Manga> fetchMangaDetails(Manga manga) async {
    final html = await _get('$_base/manga/${manga.id}');
    final pageTitle = cleanText(
      firstGroup(html, r'<title[^>]*>(.*?)</title>') ?? '',
    );
    final title = pageTitle
        .replaceFirst(RegExp(r'\s*[-–—|]\s*FMTeam\s*$'), '')
        .trim();
    final cover = firstGroup(html, '(/storage/comics/[^"\'<> ]+\\.(?:jpg|jpeg|png|webp))');
    final description = firstGroup(html, r'manga-desc[^>]*>(.*?)</div>');
    final author = firstGroup(html, r'manga-row-author[^>]*>\s*([^<]*)');
    final tags = allGroups(html, r'manga-row-tag[^>]*>([^<]+)</span>')
        .map(cleanText)
        .where((t) => t.isNotEmpty)
        .toList();
    final status = _statusFromTags(tags);
    final genres = tags
        .where((t) => !_statusWords.any((w) => t.toLowerCase().startsWith(w)))
        .expand((t) => t.contains(' - ') ? t.split(' - ') : [t])
        .map(cleanText)
        .where((g) => g.isNotEmpty)
        .toList();

    return Manga(
      id: manga.id,
      sourceId: manga.sourceId,
      title: title.isEmpty ? manga.title : title,
      coverUrl: cover == null ? manga.coverUrl : '$_base$cover',
      author: author == null
          ? manga.author
          : cleanText(author.replaceFirst(RegExp(r'^Auteur\s*:\s*'), '')),
      description: description == null
          ? manga.description
          : stripHtml(description),
      status: status ?? manga.status,
      genres: genres.isEmpty ? manga.genres : genres,
    );
  }

  // ---------------------------------------------------------------- chapitres

  @override
  Future<List<Chapter>> fetchChapters(Manga manga) async {
    final html = await _get('$_base/manga/${manga.id}');
    final chapters = <Chapter>[];
    final seen = <String>{};
    final pattern = RegExp(
      '/read/${RegExp.escape(manga.id)}/[a-z]{2,}/ch/(\\d+(?:[.,]\\d+)?)',
    );
    for (final m in pattern.allMatches(html)) {
      final url = '$_base${m[0]!}';
      if (!seen.add(url)) continue;
      final number = m[1]!.replaceAll(',', '.');
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
    final html = await _get(chapter.id);
    // Les images de chapitre vivent dans un sous-dossier
    // `/storage/comics/<slug>_<hash>/<chapitre>/NN.png` (au moins 3 segments),
    // ce qui exclut les couvertures (2 segments).
    final urls = <String>[];
    for (final m in RegExp(
      '/storage/comics/(?:[^"\'<> ]+/){2,}[^"\'<> ]+',
    ).allMatches(html)) {
      final path = m[0]!;
      if (urls.contains(path)) continue;
      if (!RegExp(r'\.(?:jpg|jpeg|png|webp|gif|avif)$', caseSensitive: false)
          .hasMatch(path)) {
        continue;
      }
      urls.add('$_base$path');
    }
    if (urls.isEmpty) {
      throw StateError('Aucune page trouvée pour ce chapitre FMTeam.');
    }
    return [
      for (var i = 0; i < urls.length; i++)
        MangaPage(
          index: i,
          imageUrl: urls[i],
          cacheKey: Uri.tryParse(urls[i])?.path ?? 'fmteam/${chapter.id}/$i',
        ),
    ];
  }

  @override
  Future<List<Genre>> fetchGenres() async => const [
        Genre(id: 'action', name: 'Action'),
        Genre(id: 'aventure', name: 'Aventure'),
        Genre(id: 'comedie', name: 'Comédie'),
        Genre(id: 'drame', name: 'Drame'),
        Genre(id: 'fantastique', name: 'Fantastique'),
        Genre(id: 'romance', name: 'Romance'),
        Genre(id: 'seinen', name: 'Seinen'),
        Genre(id: 'shonen', name: 'Shonen'),
        Genre(id: 'shojo', name: 'Shojo'),
        Genre(id: 'slice-of-life', name: 'Tranche de vie'),
      ];

  // ------------------------------------------------------------------- outils

  static const _statusWords = [
    'termin',
    'en cours',
    'en pause',
    'abandon',
    'hiatus',
  ];

  static MangaStatus? _statusFromTags(List<String> tags) {
    for (final tag in tags) {
      final t = tag.toLowerCase();
      if (t.startsWith('termin')) return MangaStatus.completed;
      if (t.startsWith('en cours') || t.startsWith('cours')) {
        return MangaStatus.ongoing;
      }
      if (t.startsWith('en pause') || t.startsWith('pause')) {
        return MangaStatus.hiatus;
      }
      if (t.startsWith('abandon')) return MangaStatus.cancelled;
    }
    return null;
  }

  static String _prettySlug(String slug) => slug
      .split('-')
      .where((p) => p.isNotEmpty)
      .map((p) => p[0].toUpperCase() + p.substring(1))
      .join(' ');

  Future<String> _get(String url) async {
    try {
      final res = await _dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: true,
          validateStatus: (code) => code != null && code < 500,
          headers: {
            'User-Agent': _userAgent,
            'Accept':
                'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'fr-FR,fr;q=0.9,en-US;q=0.8,en;q=0.7',
            'Referer': '$_base/',
          },
        ),
      );
      final code = res.statusCode ?? 0;
      final body = res.data ?? '';
      if (code == 403 || code == 503 || _looksBlocked(body)) {
        throw StateError('FMTeam est protégé/bloqué temporairement.');
      }
      if (code >= 400) throw StateError('FMTeam indisponible (HTTP $code).');
      return body;
    } on DioException {
      throw StateError('FMTeam est injoignable pour le moment.');
    }
  }

  bool _looksBlocked(String html) {
    final lower = html.toLowerCase();
    return lower.contains('cf-browser-verification') ||
        lower.contains('just a moment') ||
        lower.contains('challenge-platform');
  }
}
