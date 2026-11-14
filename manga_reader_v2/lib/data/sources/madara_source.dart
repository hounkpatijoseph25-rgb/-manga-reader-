import 'package:dio/dio.dart';

import '../models/chapter.dart';
import '../models/manga.dart';
import '../models/manga_page.dart';
import 'manga_source.dart';
import 'scrape_utils.dart';

/// Source « Mangas Origines » (https://mangas-origines.fr).
///
/// Le site utilise un thème enfant maison : les URLs de séries sont
/// `/oeuvre/<slug>/`, le catalogue est paginé par `/catalogues/page/N/` et la
/// recherche passe par `?s=<texte>&post_type=wp-manga`.
class MangasOriginesSource extends MangaSource {
  MangasOriginesSource(this._dio);

  final Dio _dio;

  static const _base = 'https://mangas-origines.fr';
  static const _perPage = 30;

  /// Le site attend un navigateur mobile : il redirige les autres agents.
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/122.0 Mobile Safari/537.36';

  @override
  String get id => 'mangas-origines';

  @override
  String get name => 'Mangas Origines';

  @override
  String get description =>
      'Scans FR — catalogue, recherche et chapitres de mangas-origines.fr';

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
      url = '$_base/?s=${Uri.encodeQueryComponent(text)}&post_type=wp-manga';
    } else if (query.genreIds.isNotEmpty) {
      url = '$_base/manga-genres/${query.genreIds.first}/';
    } else {
      // Le tri (populaire / notes / A-Z) est appliqué en JavaScript côté site :
      // on laisse donc l'ordre par défaut.
      url = '$_base/catalogues/page/$page/';
      paginated = true;
    }

    final html = await _get(url);
    final mangas = _parseCards(html);
    if (mangas.isEmpty) return const MangaPageResult([], false);
    return MangaPageResult(mangas, paginated && mangas.length >= _perPage - 10);
  }

  List<Manga> _parseCards(String html) {
    if (html.contains('Page introuvable')) return const [];
    final result = <Manga>[];
    final seen = <String>{};

    void addCard(String block) {
      final href = firstGroup(block, r'href="([^"]+)"');
      if (href == null) return;
      final slug = segmentAfter(decodeHtmlEntities(href), 'oeuvre');
      if (slug.isEmpty || !seen.add(slug)) return;

      final title = cleanText(
        firstGroup(block, r'ori-card-title[^"]*">([^<]*)') ??
            firstGroup(block, r'title="([^"]+)"') ??
            firstGroup(block, r'alt="([^"]+)"') ??
            '',
      );
      if (title.isEmpty) return;

      final cover = firstGroup(block, r'<img[^>]+data-src="([^"]+)"') ??
          firstGroup(block, r'<img[^>]+src="([^"]+)"');
      final genres = (firstGroup(block, r'ori-card-sub[^"]*">([^<]*)') ?? '')
          .split(RegExp(r'[,·•|/]'))
          .map(cleanText)
          .where((genre) => genre.isNotEmpty)
          .toList();
      final statusClass = firstGroup(block, r'ori-cat-dot\s+([a-zA-Z0-9_-]+)');

      result.add(
        Manga(
          id: slug,
          sourceId: id,
          title: title,
          coverUrl: cover == null ? null : decodeHtmlEntities(cover),
          status: _status(statusClass),
          genres: genres,
        ),
      );
    }

    final cardChunks = html.split('<a class="ori-card ori-cat-card"');
    for (final chunk in cardChunks.skip(1)) {
      addCard(_until(chunk, '</a>'));
    }

    // Fallback générique: liens vers /oeuvre/<slug>/ avec image/titre à proximité.
    if (result.isEmpty) {
      final re = RegExp(
        r'<a[^>]+href="([^"]*/oeuvre/[^"]+/?)"[^>]*>(.*?)</a>',
        dotAll: true,
        caseSensitive: false,
      );
      for (final m in re.allMatches(html)) {
        final block = '<a href="${m.group(1) ?? ''}">${m.group(2) ?? ''}</a>';
        addCard(block);
        if (result.length >= 60) break;
      }
    }

    return result;
  }

  // ------------------------------------------------------------------ détails

  @override
  Future<Manga> fetchMangaDetails(Manga manga) async {
    final html = await _get('$_base/oeuvre/${manga.id}/');
    final title = cleanText(firstGroup(html, r'ori-sr-title">([^<]*)') ?? '');
    final cover = firstGroup(
      html,
      r'<div class="ori-sr-cover">\s*<img[^>]+src="([^"]+)"',
    );
    // Le badge contient une puce interne (`<span class="ori-sr-dot">`) :
    // on saute les balises vides avant de lire le libellé.
    final statusText = stripHtml(
      firstGroup(
            html,
            r'ori-sr-badge-statut[^"]*"[^>]*>(?:\s*<span[^>]*>\s*</span>)?\s*([^<]+)',
          ) ??
          firstGroup(html, r'ori-sr-badge-statut[^"]*"[^>]*>([^<]+)') ??
          '',
    );
    final genres = allGroups(
      html,
      r'ori-sr-genre"[^>]*>([^<]*)<',
    ).map(cleanText).where((genre) => genre.isNotEmpty).toList();

    final signature = firstGroup(html, r'ori-sr-signature">(.*?)</div>') ?? '';
    final names = allGroups(
      signature,
      r'<a[^>]*>([^<]*)</a>',
    ).map(cleanText).where((name) => name.isNotEmpty).toList();

    final synopsis = firstGroup(html, r'ori-sr-syn-texte">(.*?)</div>');
    final status = statusText.isEmpty ? manga.status : _status(statusText);

    return Manga(
      id: manga.id,
      sourceId: manga.sourceId,
      title: title.isEmpty ? manga.title : title,
      coverUrl: cover == null ? manga.coverUrl : decodeHtmlEntities(cover),
      author: names.isNotEmpty ? names.first : manga.author,
      artist: names.length > 1 ? names[1] : manga.artist,
      description: synopsis == null ? manga.description : stripHtml(synopsis),
      status: status,
      genres: genres.isEmpty ? manga.genres : genres,
    );
  }

  // ---------------------------------------------------------------- chapitres

  @override
  Future<List<Chapter>> fetchChapters(Manga manga) async {
    final html = await _get('$_base/oeuvre/${manga.id}/');
    final chapters = <Chapter>[];
    final chunks = html.split('<div class="ori-chl-row');
    for (final chunk in chunks.skip(1)) {
      final number = firstGroup(chunk, r'^[^>]*data-num="([^"]*)"');
      final href =
          firstGroup(chunk, r'ori-chl-corps"[^>]*href="([^"]+)"') ??
          firstGroup(chunk, r'<a[^>]*href="([^"]+)"');
      if (href == null) continue;
      final date = firstGroup(chunk, r'ori-chl-date"[^>]*title="([^"]+)"');
      chapters.add(
        Chapter(
          id: decodeHtmlEntities(href),
          mangaId: manga.id,
          sourceId: id,
          number: number,
          title: '',
          publishedAt: parseFrenchDate(date ?? ''),
        ),
      );
    }

    chapters.sort((a, b) {
      final left = a.numberValue;
      final right = b.numberValue;
      if (left < 0 && right < 0) return 0;
      if (left < 0) return 1;
      if (right < 0) return -1;
      return left.compareTo(right);
    });
    return chapters;
  }

  @override
  Future<List<MangaPage>> fetchPages(Chapter chapter) async {
    final html = await _get(chapter.id);
    final urls = <String>[];

    void addUrl(String? raw) {
      if (raw == null) return;
      final url = decodeHtmlEntities(raw).trim();
      if (url.isEmpty || url.startsWith('data:') || urls.contains(url)) return;
      urls.add(url);
    }

    final tags = RegExp(
      r'<img[^>]*wp-manga-chapter-img[^>]*>',
      caseSensitive: false,
    ).allMatches(html);
    for (final tag in tags) {
      addUrl(firstGroup(tag[0]!, r'data-src="([^"]+)"'));
      addUrl(firstGroup(tag[0]!, r'data-lazy-src="([^"]+)"'));
      addUrl(firstGroup(tag[0]!, r'\ssrc="([^"]+)"'));
    }

    if (urls.isEmpty) {
      final reading = RegExp(
        r'<img[^>]+(?:data-src|data-lazy-src|src)="([^"]+)"[^>]*>',
        caseSensitive: false,
      ).allMatches(html);
      for (final m in reading) {
        final u = m.group(1) ?? '';
        if (u.contains('/wp-content/uploads/') || u.contains('chapter')) {
          addUrl(u);
        }
      }
    }

    if (urls.isEmpty) {
      throw StateError('Aucune page trouvée pour ce chapitre (structure du site changée ?).');
    }
    return [
      for (var i = 0; i < urls.length; i++)
        MangaPage(
          index: i,
          imageUrl: urls[i],
          cacheKey: Uri.tryParse(urls[i])?.path ?? 'mangas-origines/${chapter.id}/$i',
        ),
    ];
  }

  // ------------------------------------------------------------------ genres

  static const _genres = [
    Genre(id: 'action', name: 'Action'),
    Genre(id: 'fantasy', name: 'Fantasy'),
    Genre(id: 'aventure', name: 'Aventure'),
    Genre(id: 'drame', name: 'Drame'),
    Genre(id: 'shonen', name: 'Shonen'),
    Genre(id: 'combat', name: 'Combat'),
    Genre(id: 'comedie', name: 'Comédie'),
    Genre(id: 'romance', name: 'Romance'),
    Genre(id: 'art-martiaux', name: 'Art Martiaux'),
    Genre(id: 'surnaturel', name: 'Surnaturel'),
    Genre(id: 'isekai', name: 'Isekai'),
    Genre(id: 'slice-of-life', name: 'Slice of Life'),
    Genre(id: 'harem', name: 'Harem'),
    Genre(id: 'webcomic', name: 'Webcomic'),
    Genre(id: 'historique', name: 'Historique'),
    Genre(id: 'ecchi', name: 'Ecchi'),
    Genre(id: 'mystere', name: 'Mystère'),
    Genre(id: 'school-life', name: 'School life'),
    Genre(id: 'shojo', name: 'Shojo'),
    Genre(id: 'seinen', name: 'Seinen'),
    Genre(id: 'returner', name: 'Returner'),
    Genre(id: 'psychologique', name: 'Psychologique'),
    Genre(id: 'magie', name: 'Magie'),
    Genre(id: 'sci-fi', name: 'Sci-fi'),
    Genre(id: 'horreur', name: 'Horreur'),
    Genre(id: 'josei', name: 'Josei'),
    Genre(id: 'tragedie', name: 'Tragédie'),
    Genre(id: 'fantastique', name: 'Fantastique'),
    Genre(id: 'amitie', name: 'Amitié'),
    Genre(id: 'drama', name: 'Drama'),
    Genre(id: 'demon', name: 'Démon'),
    Genre(id: 'mature', name: 'Mature'),
    Genre(id: 'murim', name: 'Murim'),
    Genre(id: 'sport', name: 'Sport'),
    Genre(id: 'guerre', name: 'Guerre'),
    Genre(id: 'regression', name: 'Régression'),
    Genre(id: 'amour', name: 'Amour'),
    Genre(id: 'ecole', name: 'École'),
    Genre(id: 'post-apo', name: 'Post-Apo'),
    Genre(id: 'supernaturel', name: 'Supernaturel'),
    Genre(id: 'adventure', name: 'Adventure'),
    Genre(id: 'comedy', name: 'Comedy'),
    Genre(id: 'reincarnation', name: 'Réincarnation'),
    Genre(id: 'novel', name: 'Novel'),
    Genre(id: 'dark-fantasy', name: 'Dark Fantasy'),
    Genre(id: 'societe', name: 'Société'),
    Genre(id: 'yuri', name: 'Yuri'),
    Genre(id: 'sorcellerie', name: 'Sorcellerie'),
    Genre(id: 'erotique', name: 'Erotique'),
    Genre(id: 'vengeance', name: 'Vengeance'),
    Genre(id: 'jeu', name: 'Jeu'),
    Genre(id: 'bl', name: 'BL'),
    Genre(id: 'religion', name: 'Religion'),
    Genre(id: 'dystopie', name: 'Dystopie'),
    Genre(id: 'moderne', name: 'Moderne'),
    Genre(id: 'prison', name: 'Prison'),
    Genre(id: 'mort', name: 'Mort'),
    Genre(id: 'steampunk', name: 'Steampunk'),
    Genre(id: 'boys', name: 'Boys'),
    Genre(id: 'malediction', name: 'Malédiction'),
    Genre(id: 'musique', name: 'Musique'),
  ];

  @override
  Future<List<Genre>> fetchGenres() async => _genres;

  // ------------------------------------------------------------------- outils

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
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'fr-FR,fr;q=0.9,en-US;q=0.8,en;q=0.7',
            'Referer': '$_base/',
          },
        ),
      );
      final code = res.statusCode ?? 0;
      final body = res.data ?? '';
      if (code == 403 || code == 503 || _looksBlocked(body)) {
        throw StateError(
          'Mangas Origines est protégé/bloqué temporairement (Cloudflare). Réessayez plus tard.',
        );
      }
      if (code >= 400) {
        throw StateError('Mangas Origines indisponible (HTTP $code).');
      }
      return body;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 403 || code == 503) {
        throw StateError('Mangas Origines est protégé par Cloudflare pour le moment.');
      }
      throw StateError('Mangas Origines est injoignable pour le moment.');
    }
  }

  bool _looksBlocked(String html) {
    final lower = html.toLowerCase();
    return lower.contains('cf-browser-verification') ||
        lower.contains('just a moment') ||
        lower.contains('challenge-platform') ||
        lower.contains('attention required') ||
        (lower.contains('cloudflare') && lower.contains('enable javascript'));
  }

  static MangaStatus _status(String? value) {
    final text = (value ?? '').toLowerCase();
    if (text.contains('cours')) return MangaStatus.ongoing;
    if (text.contains('termin')) return MangaStatus.completed;
    if (text.contains('pause')) return MangaStatus.hiatus;
    if (text.contains('abandon')) return MangaStatus.cancelled;
    return MangaStatus.unknown;
  }

  /// Partie de [text] avant la première occurrence de [marker].
  static String _until(String text, String marker) {
    final index = text.indexOf(marker);
    return index < 0 ? text : text.substring(0, index);
  }
}
