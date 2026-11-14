import 'package:dio/dio.dart';

import '../models/chapter.dart';
import '../models/manga.dart';
import '../models/manga_page.dart';
import 'manga_source.dart';
import 'scrape_utils.dart';

/// Source « Poseidon Scans » (https://poseidon-scans.net).
///
/// Site Next.js : le catalogue est sur `/series` (pagination `?page=`,
/// recherche `?search=`), les séries sur `/serie/<slug>`, les chapitres sur
/// `/serie/<slug>/chapter/<num>`. Les données (auteur, statut, catégories,
/// chapitres, images) sont dans la charge RSC renvoyée quand on envoie
/// l'en-tête `RSC: 1`.
class PoseidonScansSource extends MangaSource {
  PoseidonScansSource(this._dio);

  final Dio _dio;

  static const _base = 'https://poseidon-scans.net';

  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/122.0 Mobile Safari/537.36';

  @override
  String get id => 'poseidon';

  @override
  String get name => 'Poseidon Scans';

  @override
  String get description =>
      'Scans FR — manhwas et webtoons de poseidon-scans.net';

  // ---------------------------------------------------------------- catalogue

  @override
  Future<MangaPageResult> fetchCatalog({
    required int page,
    required CatalogQuery query,
  }) async {
    final text = query.text.trim();

    if (query.sort == CatalogSort.latest && text.isEmpty) {
      return _latest(page);
    }

    final url =
        '$_base/series'
        '${page > 1 ? '?page=$page' : '?page=1'}'
        '${text.isEmpty ? '' : '&search=${Uri.encodeQueryComponent(text)}'}';

    final html = await _get(url);
    final mangas = _parseCards(html);
    if (mangas.isEmpty) return const MangaPageResult([], false);

    final total = RegExp(r'sur\s*(?:<!-- -->)?(\d+)(?:<!-- -->)?')
        .firstMatch(html)
        ?.group(1);
    final totalPages = int.tryParse(total ?? '');
    final hasNext = totalPages != null
        ? page < totalPages
        : mangas.length >= 20;

    return MangaPageResult(mangas, hasNext);
  }

  /// Dernières sorties via l'API JSON du site.
  Future<MangaPageResult> _latest(int page) async {
    final res = await _dio.get<dynamic>(
      '$_base/api/manga/lastchapters',
      queryParameters: {'limit': 16, 'page': page},
      options: Options(headers: _jsonHeaders),
    );
    final data = res.data;
    final list = data is Map<String, dynamic>
        ? (data['data'] as List? ?? const [])
        : (data as List? ?? const []);

    final mangas = <Manga>[];
    for (final item in list) {
      if (item is! Map) continue;
      final slug = '${item['slug'] ?? ''}';
      final title = cleanText('${item['title'] ?? ''}');
      if (slug.isEmpty || title.isEmpty) continue;
      mangas.add(
        Manga(id: slug, sourceId: id, title: title, coverUrl: _coverUrl(slug)),
      );
    }
    return MangaPageResult(mangas, mangas.length >= 16);
  }

  /// Cartes du catalogue : `a.block.group` avec un `h2` et une vignette.
  List<Manga> _parseCards(String html) {
    final result = <Manga>[];
    final seen = <String>{};

    for (final chunk in html.split('href="/serie/')) {
      final slug = RegExp(r'^([a-z0-9\-]+)"').firstMatch(chunk)?.group(1);
      if (slug == null || slug.isEmpty) continue;
      if (chunk.startsWith('$slug/chapter/')) continue;
      if (!seen.add(slug)) continue;

      final title = cleanText(
        firstGroup(chunk, r'<h2[^>]*>(.*?)</h2>') ??
            firstGroup(chunk, r'<img[^>]+alt="([^"]+)"') ??
            '',
      );
      if (title.isEmpty) continue;

      String? cover;
      final srcset = firstGroup(chunk, r'srcSet="([^"]+)"');
      if (srcset != null) {
        final encoded = firstGroup(srcset, r'url=([^&\s]+)');
        if (encoded != null) {
          final decoded = Uri.decodeComponent(decodeHtmlEntities(encoded));
          if (decoded.isNotEmpty) cover = _absolute(decoded);
        }
      }

      result.add(
        Manga(
          id: slug,
          sourceId: id,
          title: title,
          coverUrl: cover ?? _coverUrl(slug),
        ),
      );
      if (result.length >= 40) break;
    }
    return result;
  }

  // ------------------------------------------------------------------ détails

  @override
  Future<Manga> fetchMangaDetails(Manga manga) async {
    final body = await _get('$_base/serie/${manga.id}', rsc: true);

    final title = cleanText(firstGroup(body, r'<h1[^>]*>(.*?)</h1>') ?? '');
    final description = _jsonString(body, 'description');
    final status = _jsonString(body, 'status') ?? '';

    return Manga(
      id: manga.id,
      sourceId: manga.sourceId,
      title: title.isEmpty ? manga.title : title,
      coverUrl: _coverUrl(manga.id),
      author: _jsonString(body, 'author') ?? manga.author,
      artist: _jsonString(body, 'artist') ?? manga.artist,
      description: description ?? manga.description,
      status: status.isEmpty ? manga.status : _status(status),
      genres: _categories(body),
    );
  }

  List<String> _categories(String body) {
    final block = firstGroup(body, r'"categories":\[(.*?)\]');
    if (block == null) return const [];
    final names = <String>[];
    for (final match in RegExp(
      r'"name":"((?:[^"\\]|\\.)*)"',
    ).allMatches(block)) {
      final name = cleanText(_unescape(match.group(1) ?? ''));
      if (name.isEmpty || names.contains(name)) continue;
      names.add(name);
    }
    return names;
  }

  // ---------------------------------------------------------------- chapitres

  @override
  Future<List<Chapter>> fetchChapters(Manga manga) async {
    final body = await _get('$_base/serie/${manga.id}', rsc: true);
    final now = DateTime.now().toUtc();
    final chapters = <Chapter>[];
    final seen = <String>{};

    for (final match in RegExp(
      r'"number":([0-9]+(?:\.[0-9]+)?),"title":(null|"(?:[^"\\]|\\.)*"),'
      r'"createdAt":"\$D([^"]+)"([^{}]*)',
    ).allMatches(body)) {
      final number = match.group(1)!;
      if (!seen.add(number)) continue;

      final meta = match.group(4) ?? '';
      final premium = meta.contains('"isPremium":true');
      final premiumUntil = RegExp(r'"premiumUntil":"\$D([^"]+)"')
          .firstMatch(meta)
          ?.group(1);
      final locked =
          premium &&
          (premiumUntil == null ||
              (DateTime.tryParse(premiumUntil)?.toUtc().isAfter(now) ?? true));
      if (locked) continue;

      final rawTitle = match.group(2)!;
      final title = rawTitle == 'null'
          ? ''
          : _unescape(rawTitle.substring(1, rawTitle.length - 1));
      final publishedAt = DateTime.tryParse(match.group(3)!);

      chapters.add(
        Chapter(
          id: '$_base/serie/${manga.id}/chapter/$number',
          mangaId: manga.id,
          sourceId: id,
          number: number,
          title: title,
          publishedAt: publishedAt,
        ),
      );
    }

    chapters.sort((a, b) => a.numberValue.compareTo(b.numberValue));
    return chapters;
  }

  @override
  Future<List<MangaPage>> fetchPages(Chapter chapter) async {
    final body = await _get(chapter.id, rsc: true);

    final images = <MapEntry<int, String>>[];
    for (final match in RegExp(
      r'"originalUrl":"((?:[^"\\]|\\.)*)","order":([0-9]+)',
    ).allMatches(body)) {
      final url = _absolute(_unescape(match.group(1)!));
      final order = int.tryParse(match.group(2)!) ?? images.length;
      images.add(MapEntry(order, url));
    }
    images.sort((a, b) => a.key.compareTo(b.key));

    if (images.isEmpty) {
      throw StateError(
        'Chapitre réservé aux membres premium sur Poseidon Scans.',
      );
    }

    return [
      for (var i = 0; i < images.length; i++)
        MangaPage(
          index: i,
          imageUrl: images[i].value,
          cacheKey: Uri.parse(images[i].value).path,
        ),
    ];
  }

  // ------------------------------------------------------------------ genres

  @override
  Future<List<Genre>> fetchGenres() async => const [];

  // ------------------------------------------------------------------- outils

  static Map<String, String> get _jsonHeaders => {
    'User-Agent': _userAgent,
    'Accept': 'application/json',
    'Accept-Language': 'fr-FR,fr;q=0.9',
  };

  Future<String> _get(String url, {bool rsc = false}) async {
    try {
      final res = await _dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          headers: {..._jsonHeaders, if (rsc) 'RSC': '1'},
        ),
      );
      return res.data ?? '';
    } on DioException {
      throw StateError('Poseidon Scans est injoignable pour le moment.');
    }
  }

  String _coverUrl(String slug) => '$_base/api/covers/$slug.webp';

  String _absolute(String url) {
    if (url.startsWith('http')) return url;
    if (url.startsWith('/')) return '$_base$url';
    return '$_base/$url';
  }

  /// Lit `"key":"valeur"` dans la charge RSC (avec échappements JSON).
  String? _jsonString(String body, String key) {
    final match = RegExp('"$key":"((?:[^"\\\\]|\\\\.)*)"').firstMatch(body);
    if (match == null) return null;
    final value = cleanText(_unescape(match.group(1)!));
    return value.isEmpty ? null : value;
  }

  static String _unescape(String value) {
    if (!value.contains(r'\')) return value;
    final buffer = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      final char = value[i];
      if (char != r'\' || i + 1 >= value.length) {
        buffer.write(char);
        continue;
      }
      final next = value[++i];
      if (next == 'n') {
        buffer.write('\n');
      } else if (next == 'r') {
        buffer.write('\r');
      } else if (next == 't') {
        buffer.write('\t');
      } else if (next == 'u' && i + 4 < value.length) {
        final code = int.tryParse(value.substring(i + 1, i + 5), radix: 16);
        if (code != null) {
          buffer.write(String.fromCharCode(code));
          i += 4;
        } else {
          buffer.write(next);
        }
      } else {
        buffer.write(next);
      }
    }
    return buffer.toString();
  }

  static MangaStatus _status(String value) {
    final text = value.toLowerCase();
    if (text.contains('cours')) return MangaStatus.ongoing;
    if (text.contains('termin') || text.contains('complete')) {
      return MangaStatus.completed;
    }
    if (text.contains('pause') || text.contains('hiatus')) {
      return MangaStatus.hiatus;
    }
    if (text.contains('abandon') || text.contains('annul')) {
      return MangaStatus.cancelled;
    }
    return MangaStatus.unknown;
  }
}
