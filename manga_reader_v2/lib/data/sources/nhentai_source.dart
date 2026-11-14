import 'package:dio/dio.dart';

import '../models/chapter.dart';
import '../models/manga.dart';
import '../models/manga_page.dart';
import 'manga_source.dart';

/// Source nhentai via l'API publique (contenu réservé aux adultes).
class NHentaiSource extends MangaSource {
  NHentaiSource(this._dio);

  final Dio _dio;

  static const _base = 'https://nhentai.net';
  static const _api = 'https://nhentai.net/api';
  static const _img = 'https://i.nhentai.net/galleries';

  static const _ext = {
    'j': 'jpg',
    'p': 'png',
    'g': 'gif',
    'w': 'webp',
  };

  @override
  String get id => 'nhentai';

  @override
  String get name => 'nhentai';

  @override
  String get description => 'Doujins et hentai (18+) via nhentai.net';

  @override
  bool get isAdult => true;

  @override
  Future<MangaPageResult> fetchCatalog({
    required int page,
    required CatalogQuery query,
  }) async {
    final text = query.text.trim();
    final uri = text.isEmpty
        ? Uri.parse('$_api/galleries/all').replace(
            queryParameters: {'page': '$page'},
          )
        : Uri.parse('$_api/galleries/search').replace(
            queryParameters: {'query': text, 'page': '$page'},
          );
    final json = await _getJson(uri.toString());
    if (json is! Map) return const MangaPageResult([], false);
    final list = json['result'];
    if (list is! List) return const MangaPageResult([], false);
    final mangas = <Manga>[];
    for (final item in list) {
      if (item is! Map) continue;
      final mapped = _mapGallery(item.cast<String, dynamic>());
      if (mapped != null) mangas.add(mapped);
    }
    final numPages = (json['num_pages'] as num?)?.toInt() ?? page;
    return MangaPageResult(mangas, page < numPages);
  }

  @override
  Future<Manga> fetchMangaDetails(Manga manga) async {
    final json = await _getJson('$_api/gallery/${manga.id}');
    if (json is! Map) return manga;
    return _mapGallery(json.cast<String, dynamic>()) ?? manga;
  }

  @override
  Future<List<Chapter>> fetchChapters(Manga manga) async {
    int count = 0;
    try {
      final g = await _getJson('$_api/gallery/${manga.id}');
      if (g is Map) count = (g['num_pages'] as num?)?.toInt() ?? 0;
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
    final json = await _getJson('$_api/gallery/${chapter.id}');
    if (json is! Map) throw StateError('Galerie introuvable.');
    final map = json.cast<String, dynamic>();
    final mediaId = '${map['media_id'] ?? ''}';
    final images = (map['images'] as Map?)?['pages'];
    if (images is! List || mediaId.isEmpty) {
      throw StateError('Aucune page trouvée.');
    }
    final pages = <MangaPage>[];
    for (var i = 0; i < images.length; i++) {
      final img = images[i];
      if (img is! Map) continue;
      final t = '${img['t'] ?? 'j'}';
      final ext = _ext[t] ?? 'jpg';
      final url = '$_img/$mediaId/${i + 1}.$ext';
      pages.add(
        MangaPage(index: i, imageUrl: url, cacheKey: Uri.parse(url).path),
      );
    }
    if (pages.isEmpty) throw StateError('Aucune page trouvée.');
    return pages;
  }

  @override
  Future<List<Genre>> fetchGenres() async => const [];

  Manga? _mapGallery(Map<String, dynamic> json) {
    final id = json['id'];
    if (id == null) return null;
    final title = _titleOf(json['title']) ?? 'nhentai $id';
    final tags = _tagsOf(json['tags']);
    final mediaId = '${json['media_id'] ?? ''}';
    String? cover;
    final coverType = ((json['images'] as Map?)?['cover'] as Map?)?['t'];
    if (mediaId.isNotEmpty && coverType != null) {
      final ext = _ext['$coverType'] ?? 'jpg';
      cover = 'https://t.nhentai.net/galleries/$mediaId/cover.$ext';
    }
    return Manga(
      id: '$id',
      sourceId: this.id,
      title: title,
      coverUrl: cover,
      genres: tags
    );
  }

  String? _titleOf(Object? value) {
    if (value is! Map) return null;
    for (final key in ['pretty', 'english', 'japanese']) {
      final v = value[key];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  List<String> _tagsOf(Object? value) {
    if (value is! List) return const [];
    final out = <String>[];
    for (final tag in value) {
      if (tag is! Map) continue;
      final type = '${tag['type'] ?? ''}';
      if (type == 'tag' || type == 'artist' || type == 'parody') {
        final name = '${tag['name'] ?? ''}'.trim();
        if (name.isNotEmpty) out.add(name);
      }
    }
    return out.take(20).toList();
  }

  Future<Object?> _getJson(String url) async {
    try {
      final res = await _dio.get(
        url,
        options: Options(
          responseType: ResponseType.json,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36',
            'Accept': 'application/json',
            'Referer': '$_base/',
          },
        ),
      );
      return res.data;
    } on DioException {
      throw StateError('nhentai est injoignable pour le moment.');
    }
  }
}