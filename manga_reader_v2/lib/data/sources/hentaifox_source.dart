import 'package:dio/dio.dart';

import '../models/chapter.dart';
import '../models/manga.dart';
import '../models/manga_page.dart';
import 'manga_source.dart';
import 'scrape_utils.dart';

/// Source HentaiFox (contenu réservé aux adultes).
class HentaiFoxSource extends MangaSource {
  HentaiFoxSource(this._dio);

  final Dio _dio;

  static const _base = 'https://hentaifox.com';

  @override
  String get id => 'hentaifox';

  @override
  String get name => 'HentaiFox';

  @override
  String get description => 'Doujins et hentai (18+) via hentaifox.com';

  @override
  bool get isAdult => true;

  @override
  Future<MangaPageResult> fetchCatalog({
    required int page,
    required CatalogQuery query,
  }) async {
    final text = query.text.trim();
    final url = text.isEmpty
        ? '$_base/pag/$page/'
        : '$_base/search/?q=${Uri.encodeQueryComponent(text)}&page=$page';
    final html = await _get(url);
    final mangas = <Manga>[];
    final seen = <String>{};
    final re = RegExp(
      r'href="/gallery/(\d+)/"[^>]*>.*?<img[^>]+(?:data-src|src)="([^"]+)"[^>]*>.*?<div class="caption">\s*([^<]+)\s*</div>',
      dotAll: true,
      caseSensitive: false,
    );
    for (final m in re.allMatches(html)) {
      final id = m[1]!;
      if (!seen.add(id)) continue;
      mangas.add(
        Manga(
          id: id,
          sourceId: this.id,
          title: cleanText(m[3] ?? ''),
          coverUrl: absoluteUrl(_base, decodeHtmlEntities(m[2] ?? '')),
        ),
      );
    }
    if (mangas.isEmpty) {
      final re2 = RegExp(
        r'href="/gallery/(\d+)/"[^>]*>.*?<img[^>]+(?:data-src|src)="([^"]+)"[^>]*alt="([^"]*)"',
        dotAll: true,
        caseSensitive: false,
      );
      for (final m in re2.allMatches(html)) {
        final id = m[1]!;
        if (!seen.add(id)) continue;
        mangas.add(
          Manga(
            id: id,
            sourceId: this.id,
            title: cleanText(m[3] ?? 'Gallery $id'),
            coverUrl: absoluteUrl(_base, decodeHtmlEntities(m[2] ?? '')),
          ),
        );
      }
    }
    final hasNext = html.contains('/pag/${page + 1}/') ||
        html.contains('page=${page + 1}') ||
        html.contains('>Next<');
    return MangaPageResult(mangas, hasNext);
  }

  @override
  Future<Manga> fetchMangaDetails(Manga manga) async {
    final html = await _get('$_base/gallery/${manga.id}/');
    final title = cleanText(
      firstGroup(html, r'<h1[^>]*>([^<]+)</h1>') ?? manga.title,
    );
    final cover = firstGroup(
          html,
          r'class="cover"[^>]*>.*?<img[^>]+(?:data-src|src)="([^"]+)"',
        ) ??
        firstGroup(html, r'<img[^>]+(?:data-src|src)="([^"]+)"[^>]*class="[^"]*cover');
    final tags = <String>[];
    for (final m in RegExp(
      r'href="/tag/[^"]+/"[^>]*>([^<]+)<',
      caseSensitive: false,
    ).allMatches(html)) {
      final t = cleanText(m[1] ?? '');
      if (t.isNotEmpty) tags.add(t);
    }
    return Manga(
      id: manga.id,
      sourceId: manga.sourceId,
      title: title,
      coverUrl: cover == null ? manga.coverUrl : absoluteUrl(_base, decodeHtmlEntities(cover)),
      genres: tags.take(20).toList()
    );
  }

  @override
  Future<List<Chapter>> fetchChapters(Manga manga) async {
    int count = 0;
    try {
      final html = await _get('$_base/gallery/${manga.id}/');
      final pagesText = firstGroup(html, r'>(\d+)\s*pages?<') ?? firstGroup(html, r'of\s+(\d+)');
      count = int.tryParse(pagesText ?? '') ?? 0;
    } catch (_) {}
    return [
      Chapter(
        id: manga.id,
        mangaId: manga.id,
        sourceId: id,
        number: '1',
        title: count > 0 ? 'Lecture ($count pages)' : 'Lecture',
        pageCount: count,
      ),
    ];
  }

  @override
  Future<List<MangaPage>> fetchPages(Chapter chapter) async {
    final first = await _get('$_base/gallery/${chapter.id}/1/');
    final urls = <String>[];
    void collect(String html) {
      for (final m in RegExp(
        r'<img[^>]+(?:data-src|src)="([^"]+/galleries/\d+/[^"]+\.(?:jpg|jpeg|png|webp|gif))"',
        caseSensitive: false,
      ).allMatches(html)) {
        final u = absoluteUrl(_base, decodeHtmlEntities(m[1]!));
        if (!urls.contains(u)) urls.add(u);
      }
      for (final m in RegExp(
        r'<img[^>]+(?:data-src|src)="([^"]+)"[^>]*class="[^"]*lazy[^"]*"',
        caseSensitive: false,
      ).allMatches(html)) {
        final u = absoluteUrl(_base, decodeHtmlEntities(m[1]!));
        if (u.contains('/galleries/') && !urls.contains(u)) urls.add(u);
      }
    }

    collect(first);
    final countText = firstGroup(first, r'>(\d+)\s*pages?<') ??
        firstGroup(first, r'of\s+(\d+)');
    final pageCount = int.tryParse(countText ?? '') ?? 0;
    final maxPages = pageCount > 0 ? (pageCount > 60 ? 60 : pageCount) : 0;
    for (var p = 2; p <= maxPages && urls.length < pageCount; p++) {
      try {
        final html = await _get('$_base/gallery/${chapter.id}/$p/');
        final before = urls.length;
        collect(html);
        if (urls.length == before) break;
      } catch (_) {
        break;
      }
    }
    if (urls.isEmpty) throw StateError('Aucune page trouvée.');
    return [
      for (var i = 0; i < urls.length; i++)
        MangaPage(index: i, imageUrl: urls[i], cacheKey: Uri.parse(urls[i]).path),
    ];
  }

  @override
  Future<List<Genre>> fetchGenres() async => const [];

  Future<String> _get(String url) async {
    try {
      final res = await _dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36',
            'Accept-Language': 'en-US,en;q=0.9',
            'Referer': '$_base/',
          },
        ),
      );
      return res.data ?? '';
    } on DioException {
      throw StateError('HentaiFox est injoignable pour le moment.');
    }
  }
}