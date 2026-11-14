import 'package:dio/dio.dart';

import '../models/chapter.dart';
import '../models/manga.dart';
import '../models/manga_page.dart';
import 'manga_source.dart';
import 'scrape_utils.dart';

/// Source « Scan-VF » (https://www.scan-vf.net).
///
/// Catalogue `/manga-list` (recherche `?search=…`, catégories
/// `/manga-list/category/<slug>`), séries `/<slug>`, chapitres
/// `/<slug>/chapitre-<n>`. Les images du lecteur sont dans
/// `/uploads/manga/<slug>/chapters/<chapitre>/<page>.webp`.
class ScanVfSource extends MangaSource {
  ScanVfSource(this._dio);

  final Dio _dio;

  static const _base = 'https://www.scan-vf.net';

  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/122.0 Mobile Safari/537.36';

  List<Genre>? _genres;

  @override
  String get id => 'scanvf';

  @override
  String get name => 'Scan-VF';

  @override
  String get description =>
      'Scans FR — mangas et webtoons de scan-vf.net';

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
      url = '$_base/manga-list?search=${Uri.encodeQueryComponent(text)}';
    } else if (query.genreIds.isNotEmpty) {
      url = '$_base/manga-list/category/${query.genreIds.first}'
          '${page > 1 ? '?page=$page' : ''}';
      paginated = true;
    } else {
      url = '$_base/manga-list${page > 1 ? '?page=$page' : ''}';
      paginated = true;
    }

    final html = await _get(url);
    final mangas = _parseCards(html);
    if (mangas.isEmpty) return const MangaPageResult([], false);
    return MangaPageResult(mangas, paginated && mangas.length >= 15);
  }

  /// Cartes de l'annuaire : `<div class="media">` avec vignette et titre.
  List<Manga> _parseCards(String html) {
    final result = <Manga>[];
    final seen = <String>{};
    for (final chunk in html.split('<div class="media"')) {
      final href = firstGroup(
        chunk,
        r'href="https://www\.scan-vf\.net/([a-z0-9_\-]+)"',
      );
      if (href == null) continue;
      if (href == 'manga-list' || href == 'latest-release') continue;
      if (!seen.add(href)) continue;

      final title = cleanText(
        firstGroup(chunk, r'class="chart-title"><strong>([^<]+)</strong>') ??
            firstGroup(chunk, r"alt='([^']+)'") ??
            firstGroup(chunk, r'<h5[^>]*>\s*([^<]+)') ??
            '',
      );
      if (title.isEmpty) continue;

      final cover = firstGroup(chunk, r"<img[^>]+src='([^']+)'");
      result.add(
        Manga(
          id: href,
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
    final html = await _get('$_base/${manga.id}');

    final title = cleanText(
      firstGroup(
            html,
            r'<h2 class="widget-title"[^>]*>\s*([^<]+?)\s*</h2>',
          ) ??
          '',
    );
    final cover = firstGroup(
      html,
      "<img class=\"img-responsive\" src='([^']+)'",
    );
    final status = cleanText(
      stripHtml(
        firstGroup(html, r'<dt>Statut</dt>\s*<dd>(.*?)</dd>') ?? '',
      ),
    );
    final author = cleanText(
      stripHtml(
        firstGroup(html, r'<dt>Auteur\(s\)</dt>\s*<dd>(.*?)</dd>') ?? '',
      ),
    );
    final description = firstGroup(
      html,
      r'<div class="manga-description"[^>]*>(.*?)</div>',
    );

    return Manga(
      id: manga.id,
      sourceId: manga.sourceId,
      title: title.isEmpty ? manga.title : title,
      coverUrl: cover == null ? manga.coverUrl : decodeHtmlEntities(cover),
      author: author.isEmpty ? manga.author : author,
      description: description == null
          ? manga.description
          : stripHtml(description),
      status: status.isEmpty ? manga.status : _status(status),
      genres: _genresFromPage(html),
    );
  }

  List<String> _genresFromPage(String html) {
    final names = <String>[];
    final matches = RegExp(
      r'href="[^"]*manga-list/category/([^"/]+)"[^>]*>([^<]*)<',
    ).allMatches(html);
    for (final match in matches) {
      final name = cleanText(match[2] ?? '');
      if (name.isEmpty) continue;
      if (!names.contains(name)) names.add(name);
    }
    return names;
  }

  // ---------------------------------------------------------------- chapitres

  @override
  Future<List<Chapter>> fetchChapters(Manga manga) async {
    final html = await _get('$_base/${manga.id}');
    final start = html.indexOf('<ul class="chapters">');
    if (start < 0) return const [];
    var end = html.indexOf('</ul>', start);
    if (end < 0) end = html.length;
    final block = html.substring(start, end);

    final chapters = <Chapter>[];
    for (final chunk in block.split('<li')) {
      final href = firstGroup(chunk, r'href="([^"]*/chapitre-[^"]+)"');
      if (href == null) continue;
      final number =
          RegExp(r'chapitre-(\d+(?:[.,]\d+)?)')
              .firstMatch(href)
              ?.group(1)
              ?.replaceAll(',', '.') ??
          _firstNumber(cleanText(stripHtml(chunk)));
      final label = cleanText(stripHtml(chunk));
      final em = cleanText(firstGroup(chunk, r'<em>([^<]*)</em>') ?? '');
      final date = firstGroup(chunk, r'date-chapter-title-rtl">\s*([^<]+)<');

      chapters.add(
        Chapter(
          id: decodeHtmlEntities(href),
          mangaId: manga.id,
          sourceId: id,
          number: number,
          title: em.isEmpty ? _titleFromLabel(label) : em,
          publishedAt: date == null ? null : parseFrenchDate(cleanText(date)),
        ),
      );
    }

    // Le site liste du plus récent au plus ancien.
    chapters.sort((a, b) => a.numberValue.compareTo(b.numberValue));
    return chapters;
  }

  /// « One Piece 1198 » → chaîne vide (le titre utile est dans `<em>`).
  String _titleFromLabel(String label) {
    final cleaned = label.replaceFirst(RegExp(r'^.*?\d+\s*:?\s*'), '');
    return cleaned == label ? '' : cleaned;
  }

  @override
  Future<List<MangaPage>> fetchPages(Chapter chapter) async {
    final html = await _get(chapter.id);
    var urls = _imagesFromHtml(html);
    if (urls.isEmpty) urls = _imagesFromJson(html, chapter.id);
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

  List<String> _imagesFromHtml(String html) {
    final found = <String>[];
    final matches = RegExp(
      "https://www\\.scan-vf\\.net/uploads/manga/[^\"']+/chapters/"
      "[^\"']+\\.(?:webp|jpg|jpeg|png)",
    ).allMatches(html);
    for (final match in matches) {
      final url = match[0]!;
      if (!found.contains(url)) found.add(url);
    }
    return found;
  }

  /// Secours : le lecteur déclare `pages = [{"page_image":"01.webp",…}]`.
  List<String> _imagesFromJson(String html, String chapterUrl) {
    final segments = Uri.parse(chapterUrl).pathSegments;
    if (segments.length < 2) return const [];
    final dir = '$_base/uploads/manga/${segments[0]}/chapters/${segments[1]}';
    final result = <String>[];
    for (final match in RegExp(r'"page_image"\s*:\s*"([^"]+)"').allMatches(
      html,
    )) {
      result.add('$dir/${match[1]}');
    }
    return result;
  }

  // ------------------------------------------------------------------ genres

  @override
  Future<List<Genre>> fetchGenres() async {
    final cached = _genres;
    if (cached != null) return cached;

    final List<Genre> genres;
    try {
      final html = await _get('$_base/manga-list');
      final byId = <String, Genre>{};
      final matches = RegExp(
        r'href="[^"]*manga-list/category/([^"/]+)"[^>]*>([^<]*)<',
      ).allMatches(html);
      for (final match in matches) {
        final slug = match[1]!;
        final name = cleanText(match[2] ?? '');
        byId.putIfAbsent(
          slug,
          () => Genre(id: slug, name: name.isEmpty ? _label(slug) : name),
        );
      }
      genres = byId.values.toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    } on StateError {
      _genres = const [];
      return const [];
    }
    _genres = genres;
    return genres;
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
      throw StateError('Scan-VF est injoignable pour le moment.');
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
}
