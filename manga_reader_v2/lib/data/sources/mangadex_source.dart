import 'package:dio/dio.dart';

import '../models/chapter.dart';
import '../models/manga.dart';
import '../models/manga_page.dart';
import 'manga_source.dart';

/// Source basée sur l'API publique de MangaDex (https://api.mangadex.org).
class MangaDexSource extends MangaSource {
  MangaDexSource(
    this._dio, {
    required this._language,
    required this._dataSaver,
    this._id = 'mangadex',
    this._name = 'MangaDex',
    this._description =
        "Catalogue communautaire via l'API publique de MangaDex",
    this._adult = false,
    this._ratings = const ['safe', 'suggestive'],
  });

  final Dio _dio;
  final String Function() _language;
  final bool Function() _dataSaver;
  final String _id;
  final String _name;
  final String _description;
  final bool _adult;
  final List<String> _ratings;

  static const _host = 'api.mangadex.org';
  static const _pageSize = 20;

  List<Genre>? _genres;

  @override
  String get id => _id;

  @override
  String get name => _name;

  @override
  String get description => _description;

  @override
  bool get isAdult => _adult;

  // ---------------------------------------------------------------- catalogue

  @override
  Future<MangaPageResult> fetchCatalog({
    required int page,
    required CatalogQuery query,
  }) async {
    final offset = (page - 1) * _pageSize;
    final text = query.text.trim();
    final params = <String, dynamic>{
      'limit': '$_pageSize',
      'offset': '$offset',
      'includes[]': ['cover_art', 'author', 'artist'],
      'contentRating[]': _ratings,
      'availableTranslatedLanguage[]': [_language()],
      'hasAvailableChapters': 'true',
    };
    if (text.isNotEmpty) params['title'] = text;
    if (query.genreIds.isNotEmpty) {
      params['includedTags[]'] = query.genreIds.toList();
    }
    switch (query.sort) {
      case CatalogSort.popularity:
        // Avec un texte de recherche, on laisse MangaDex trier par pertinence.
        if (text.isEmpty) params['order[followedCount]'] = 'desc';
      case CatalogSort.latest:
        params['order[latestUploadedChapter]'] = 'desc';
      case CatalogSort.title:
        params['order[title]'] = 'asc';
    }

    final res = await _dio.getUri<Map<String, dynamic>>(
      Uri.https(_host, '/manga', params),
    );
    final body = res.data ?? const <String, dynamic>{};
    final items = ((body['data'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => _parseManga(m.cast<String, dynamic>()))
        .toList();
    final total = (body['total'] as num?)?.toInt() ?? 0;
    return MangaPageResult(items, offset + items.length < total);
  }

  @override
  Future<Manga> fetchMangaDetails(Manga manga) async {
    final uri = Uri.https(_host, '/manga/${manga.id}', {
      'includes[]': ['cover_art', 'author', 'artist'],
    });
    final res = await _dio.getUri<Map<String, dynamic>>(uri);
    final data = res.data?['data'];
    if (data is! Map) return manga;
    return _parseManga(data.cast<String, dynamic>(), coverSize: 512);
  }

  @override
  Future<List<Chapter>> fetchChapters(Manga manga) async {
    final preferred = await _fetchChapters(manga, _language());
    if (preferred.isNotEmpty) return preferred;
    // MangaDex annonce parfois une langue comme disponible alors qu'aucun
    // chapitre n'existe réellement : on retombe sur l'anglais, puis sur toutes
    // les langues, pour ne jamais afficher une fiche vide.
    final english = await _fetchChapters(manga, 'en');
    if (english.isNotEmpty) return english;
    return _fetchChapters(manga, null);
  }

  /// Chapitres du manga filtrés par [language] (`null` = toutes les langues).
  Future<List<Chapter>> _fetchChapters(Manga manga, String? language) async {
    const limit = 500;
    final all = <Chapter>[];
    var offset = 0;
    while (true) {
      final params = <String, dynamic>{
        'limit': '$limit',
        'offset': '$offset',
        'includes[]': ['scanlation_group'],
        'includeExternalUrl': '0',
        'order[chapter]': 'asc',
      };
      if (language != null) params['translatedLanguage[]'] = [language];
      final uri = Uri.https(_host, '/manga/${manga.id}/feed', params);
      final res = await _dio.getUri<Map<String, dynamic>>(uri);
      final body = res.data ?? const <String, dynamic>{};
      final list = ((body['data'] as List?) ?? const []).whereType<Map>();
      for (final c in list) {
        all.add(_parseChapter(c.cast<String, dynamic>(), manga));
      }
      final total = (body['total'] as num?)?.toInt() ?? 0;
      offset += limit;
      if (offset >= total || list.isEmpty) break;
    }

    // Plusieurs groupes peuvent avoir traduit le même chapitre : on n'en garde qu'un.
    final byNumber = <String, Chapter>{};
    for (final c in all) {
      if (c.pageCount <= 0) continue;
      byNumber.putIfAbsent(c.number ?? c.id, () => c);
    }
    return byNumber.values.toList()
      ..sort((a, b) => a.numberValue.compareTo(b.numberValue));
  }

  @override
  Future<List<MangaPage>> fetchPages(Chapter chapter) async {
    final res = await _dio.getUri<Map<String, dynamic>>(
      Uri.https(_host, '/at-home/server/${chapter.id}'),
    );
    final body = res.data ?? const <String, dynamic>{};
    final baseUrl = body['baseUrl'] as String?;
    final info = (body['chapter'] as Map?)?.cast<String, dynamic>();
    final hash = info?['hash'] as String?;
    if (baseUrl == null || info == null || hash == null) {
      throw StateError('Réponse inattendue du serveur MangaDex.');
    }
    // Tous les chapitres n'ont pas de version « data-saver » : dans ce cas on
    // retombe sur les images normales au lieu de planter.
    final saverFiles = info['dataSaver'];
    final useSaver = _dataSaver() && saverFiles is List && saverFiles.isNotEmpty;
    final raw = useSaver ? saverFiles : (info['data'] ?? info['dataSaver']);
    final files = ((raw as List?) ?? const []).map((e) => '$e').toList();
    final folder = useSaver ? 'data-saver' : 'data';
    return [
      for (var i = 0; i < files.length; i++)
        MangaPage(
          index: i,
          imageUrl: '$baseUrl/$folder/$hash/${files[i]}',
          cacheKey: '$folder/$hash/${files[i]}',
        ),
    ];
  }

  @override
  Future<List<Genre>> fetchGenres() async {
    final cached = _genres;
    if (cached != null) return cached;
    final res = await _dio.getUri<Map<String, dynamic>>(
      Uri.https(_host, '/manga/tag'),
    );
    final body = res.data ?? const <String, dynamic>{};
    final genres = <Genre>[];
    for (final tag in ((body['data'] as List?) ?? const []).whereType<Map>()) {
      final attrs = tag['attributes'];
      if (attrs is! Map) continue;
      final group = attrs['group'];
      if (group != 'genre' && group != 'theme') continue;
      final label = _localized(attrs['name']);
      if (label.isNotEmpty) genres.add(Genre(id: '${tag['id']}', name: label));
    }
    genres.sort((a, b) => a.name.compareTo(b.name));
    _genres = genres;
    return genres;
  }

  // ------------------------------------------------------------------ parsing

  /// Les textes MangaDex sont de la forme {"en": "...", "fr": "..."}.
  String _localized(Object? value, {String? prefer}) {
    if (value is! Map || value.isEmpty) return '';
    if (prefer != null) {
      final preferred = value[prefer];
      if (preferred is String && preferred.isNotEmpty) return preferred;
    }
    final english = value['en'];
    if (english is String && english.isNotEmpty) return english;
    for (final v in value.values) {
      if (v is String && v.isNotEmpty) return v;
    }
    return '';
  }

  MangaStatus _status(Object? value) => switch (value) {
    'ongoing' => MangaStatus.ongoing,
    'completed' => MangaStatus.completed,
    'hiatus' => MangaStatus.hiatus,
    'cancelled' => MangaStatus.cancelled,
    _ => MangaStatus.unknown,
  };

  Manga _parseManga(Map<String, dynamic> json, {int coverSize = 256}) {
    final mangaId = json['id'] as String;
    final attrs =
        (json['attributes'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final rels = ((json['relationships'] as List?) ?? const [])
        .whereType<Map>()
        .toList();

    String? relation(String type, String field) {
      for (final r in rels) {
        if (r['type'] != type) continue;
        final a = r['attributes'];
        if (a is Map && a[field] is String) return a[field] as String;
      }
      return null;
    }

    final fileName = relation('cover_art', 'fileName');

    final tags = <String>[];
    for (final t in ((attrs['tags'] as List?) ?? const []).whereType<Map>()) {
      final label = _localized((t['attributes'] as Map?)?['name']);
      if (label.isNotEmpty) tags.add(label);
    }

    var title = _localized(attrs['title']);
    if (title.isEmpty) {
      for (final alt in (attrs['altTitles'] as List?) ?? const []) {
        title = _localized(alt);
        if (title.isNotEmpty) break;
      }
    }
    if (title.isEmpty) title = 'Sans titre';

    return Manga(
      id: mangaId,
      sourceId: id,
      title: title,
      coverUrl: fileName == null
          ? null
          : 'https://uploads.mangadex.org/covers/$mangaId/$fileName.$coverSize.jpg',
      author: relation('author', 'name'),
      artist: relation('artist', 'name'),
      description: _localized(attrs['description'], prefer: _language()),
      status: _status(attrs['status']),
      genres: tags,
    );
  }

  Chapter _parseChapter(Map<String, dynamic> json, Manga manga) {
    final attrs =
        (json['attributes'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    String? group;
    for (final r
        in ((json['relationships'] as List?) ?? const []).whereType<Map>()) {
      if (r['type'] != 'scanlation_group') continue;
      final a = r['attributes'];
      if (a is Map && a['name'] is String) group = a['name'] as String;
    }
    final published =
        (attrs['readableAt'] ?? attrs['publishAt'] ?? '') as String;
    return Chapter(
      id: json['id'] as String,
      mangaId: manga.id,
      sourceId: id,
      number: attrs['chapter'] as String?,
      title: (attrs['title'] as String?) ?? '',
      volume: attrs['volume'] as String?,
      publishedAt: DateTime.tryParse(published),
      pageCount: (attrs['pages'] as num?)?.toInt() ?? 0,
      scanlator: group,
    );
  }
}
