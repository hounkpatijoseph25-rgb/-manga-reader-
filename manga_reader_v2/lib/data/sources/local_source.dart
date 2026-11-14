import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/chapter.dart';
import '../models/manga.dart';
import '../models/manga_page.dart';
import 'manga_source.dart';

/// Bibliothèque locale.
///
/// L'utilisateur choisit un dossier : l'application cherche **récursivement**
/// les mangas/webtoons qu'il contient, quelle que soit l'arborescence.
///
/// Un dossier est considéré comme un manga quand :
/// - il contient au moins un sous-dossier qui contient lui-même des images
///   (les chapitres), ou un fichier `.cbz` / `.zip` / `.cbr` ;
/// - ou il contient directement au moins 3 images (webtoon « à plat ») ;
/// - ou il contient une seule image et aucun sous-dossier.
///
/// Sinon il est traité comme un dossier de rangement (par exemple `Mangas/`,
/// `Webtoons/`) et on continue à descendre à l'intérieur.
///
/// Les traitements lourds (parcours du disque) sont faits dans un isolate :
/// l'interface ne se fige jamais, même avec une grosse collection.
class LocalMangaSource extends MangaSource {
  LocalMangaSource({required this.rootPath, this.coverOverride});

  /// Renvoie le dossier choisi par l'utilisateur (chaîne vide = aucun).
  final String? Function() rootPath;

  /// Couverture choisie à la main par l'utilisateur : `dossier manga → image`.
  final String? Function(String mangaPath)? coverOverride;

  List<List<String>>? _cache;
  String? _cacheRoot;
  DateTime? _cacheTime;

  @override
  String get id => 'local';

  @override
  String get name => 'Bibliothèque locale';

  @override
  String get description {
    final root = _root;
    if (root == null) return 'Aucun dossier importé';
    if (!Directory(root).existsSync()) return 'Dossier introuvable : $root';
    if (!_readable(Directory(root))) {
      return 'Dossier illisible — autorise « Accès à tous les fichiers » '
          'dans les réglages Android';
    }
    return root;
  }

  @override
  String? get iconUrl => null;

  String? get _root {
    final path = rootPath();
    if (path == null || path.trim().isEmpty) return null;
    return path;
  }

  // --------------------------------------------------------------- couverture

  String? _cover(Directory dir) {
    if (!dir.existsSync()) return null;
    final override = coverOverride?.call(dir.path);
    if (override != null && override.isNotEmpty && File(override).existsSync()) {
      return override;
    }
    return _coverFor(dir);
  }

  /// Échantillon d'images du dossier, proposé pour choisir la présentation.
  static List<String> coverCandidates(String dirPath, {int limit = 60}) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return const [];
    final result = <String>[];
    void add(List<File> files) {
      for (final f in files) {
        if (result.length >= limit) return;
        if (!result.contains(f.path)) result.add(f.path);
      }
    }

    add(_images(dir));
    for (final sub in _subDirs(dir)) {
      if (result.length >= limit) break;
      add(_images(sub));
      for (final deep in _subDirs(sub)) {
        if (result.length >= limit) break;
        add(_images(deep));
      }
    }
    return result;
  }

  // ----------------------------------------------------------------- catalogue

  @override
  Future<MangaPageResult> fetchCatalog({
    required int page,
    required CatalogQuery query,
  }) async {
    final root = _root;
    if (root == null) return const MangaPageResult([], false);
    final rootDir = Directory(root);
    if (!rootDir.existsSync() || !_readable(rootDir)) {
      return const MangaPageResult([], false);
    }

    final rows = await _discovered(rootDir);
    final text = query.text.trim().toLowerCase();

    final mangas = <Manga>[];
    for (final row in rows) {
      final path = row[0];
      final title = row[1];
      if (text.isNotEmpty && !title.toLowerCase().contains(text)) continue;
      final cover = _overrideFor(path) ?? (row[2].isEmpty ? null : row[2]);
      mangas.add(
        Manga(id: path, sourceId: id, title: title, coverUrl: cover),
      );
    }

    const pageSize = 20;
    final start = (page - 1) * pageSize;
    if (start >= mangas.length) return const MangaPageResult([], false);
    final end = (start + pageSize).clamp(0, mangas.length);
    return MangaPageResult(mangas.sublist(start, end), end < mangas.length);
  }

  /// Couverture choisie à la main, si elle existe encore.
  String? _overrideFor(String mangaPath) {
    final override = coverOverride?.call(mangaPath);
    if (override != null &&
        override.isNotEmpty &&
        File(override).existsSync()) {
      return override;
    }
    return null;
  }

  /// Découverte des mangas, mise en cache quelques minutes (le parcours du
  /// disque est coûteux) et exécutée hors du thread principal.
  Future<List<List<String>>> _discovered(Directory root) async {
    final cached = _cache;
    final time = _cacheTime;
    if (cached != null &&
        _cacheRoot == root.path &&
        time != null &&
        DateTime.now().difference(time) < const Duration(minutes: 2)) {
      return cached;
    }
    final rows = await compute(_discoverTask, root.path);
    _cache = rows;
    _cacheRoot = root.path;
    _cacheTime = DateTime.now();
    return rows;
  }

  @override
  Future<Manga> fetchMangaDetails(Manga manga) async {
    final dir = Directory(manga.id);
    if (!dir.existsSync()) return manga;
    return Manga(
      id: manga.id,
      sourceId: manga.sourceId,
      title: manga.title,
      // La couverture est recalculée (le choix manuel est prioritaire sur
      // celle du catalogue, qui peut être périmée).
      coverUrl: _cover(dir) ?? manga.coverUrl,
      author: manga.author,
      artist: manga.artist,
      description: manga.description,
      status: manga.status,
      genres: manga.genres,
    );
  }

  // ----------------------------------------------------------------- chapitres

  @override
  Future<List<Chapter>> fetchChapters(Manga manga) async {
    final dir = Directory(manga.id);
    if (!dir.existsSync()) return const [];

    final rows = await compute(_collectTask, [dir.path, dir.path]);
    return [
      for (var i = 0; i < rows.length; i++)
        Chapter(
          id: rows[i][0],
          mangaId: manga.id,
          sourceId: id,
          number: _chapterNumber(rows[i][1]) ?? '${i + 1}',
          title: rows[i][1],
          pageCount: int.tryParse(rows[i][2]) ?? 0,
        ),
    ];
  }

  @override
  Future<List<MangaPage>> fetchPages(Chapter chapter) async {
    final path = chapter.id;
    final List<String> files;
    if (_isArchive(path)) {
      files = _images(await _unzip(path)).map((f) => f.path).toList();
    } else {
      final dir = Directory(path);
      var images = _images(dir);
      if (images.isEmpty) {
        // Images rangées dans un unique sous-dossier (« scans/ »). On ne prend
        // QUE le premier sous-dossier trouvé : ça évite de mélanger plusieurs
        // chapitres si l'arborescence n'est pas celle attendue.
        for (final sub in _subDirs(dir)) {
          final found = _deepImages(sub, 2);
          if (found.isNotEmpty) {
            images = found;
            break;
          }
        }
      }
      files = images.map((f) => f.path).toList();
    }
    return [
      for (var i = 0; i < files.length; i++)
        MangaPage(
          index: i,
          imageUrl: '',
          localPath: files[i],
          cacheKey: files[i],
        ),
    ];
  }

  Future<Directory> _unzip(String filePath) async {
    final temp = await getTemporaryDirectory();
    final name = p
        .basenameWithoutExtension(filePath)
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    // Le chemin complet entre dans la clé : deux « Chapitre 1.cbz » de séries
    // différentes ne partagent plus le même dossier temporaire.
    final out = Directory(
      p.join(temp.path, 'manga_reader_cbz', '${name}_${_shortHash(filePath)}'),
    );
    if (out.existsSync() && _images(out).isNotEmpty) return out;

    await out.create(recursive: true);
    final stream = InputFileStream(filePath);
    try {
      final archive = ZipDecoder().decodeStream(stream);
      for (final f in archive.files) {
        if (!f.isFile || !_isImage(f.name)) continue;
        final target = File(p.join(out.path, p.basename(f.name)));
        await target.parent.create(recursive: true);
        await target.writeAsBytes(f.content as List<int>);
      }
    } catch (error) {
      throw StateError('Archive illisible : ${p.basename(filePath)} ($error)');
    } finally {
      stream.closeSync();
    }
    return out;
  }

  @override
  Future<List<Genre>> fetchGenres() async => const [];
}

// ============================================================================
// Fonctions de parcours du disque (hors classe : elles tournent dans un isolate)
// ============================================================================

const List<String> _imageExtensions = [
  '.jpg',
  '.jpeg',
  '.png',
  '.webp',
  '.gif',
  '.bmp',
  '.avif',
];
const List<String> _archiveExtensions = ['.cbz', '.zip', '.cbr'];
const List<String> _coverNames = [
  'cover',
  'folder',
  'poster',
  'thumbnail',
  'default',
  'presentation',
];

const int _maxChapterDepth = 8;
const int _maxDiscoverDepth = 5;
const int _maxCoverDepth = 4;

/// Garde-fous : on ne veut ni mémoire infinie, ni parcours sans fin.
const int _maxDiscovered = 5000;
const int _maxUnits = 5000;

bool _isImage(String path) =>
    _imageExtensions.contains(p.extension(path).toLowerCase());

bool _isArchive(String path) =>
    _archiveExtensions.contains(p.extension(path).toLowerCase());

bool _hidden(String path) => p.basename(path).startsWith('.');

/// `listSync()` qui ne jette jamais (dossier illisible = liste vide).
List<FileSystemEntity> _safeList(Directory dir) {
  try {
    return dir.listSync(followLinks: false);
  } catch (_) {
    return const [];
  }
}

bool _readable(Directory dir) {
  try {
    dir.listSync(followLinks: false).take(1).toList();
    return true;
  } catch (_) {
    return false;
  }
}

/// Tri « naturel » : `Chapitre 2` avant `Chapitre 10`.
int _naturalCompare(String a, String b) {
  final pattern = RegExp(r'(\d+)|(\D+)');
  final ma = pattern.allMatches(a.toLowerCase()).toList();
  final mb = pattern.allMatches(b.toLowerCase()).toList();
  for (var i = 0; i < ma.length && i < mb.length; i++) {
    final sa = ma[i].group(0)!;
    final sb = mb[i].group(0)!;
    final na = int.tryParse(sa);
    final nb = int.tryParse(sb);
    if (na != null && nb != null) {
      final c = na.compareTo(nb);
      if (c != 0) return c;
    } else {
      final c = sa.compareTo(sb);
      if (c != 0) return c;
    }
  }
  return ma.length.compareTo(mb.length);
}

/// Images **directement** dans [dir], triées.
List<File> _images(Directory dir) {
  final files = _safeList(dir)
      .whereType<File>()
      .where((f) => !_hidden(f.path) && _isImage(f.path))
      .toList();
  files.sort((a, b) => _naturalCompare(a.path, b.path));
  return files;
}

List<File> _archives(Directory dir) => _safeList(dir)
    .whereType<File>()
    .where((f) => !_hidden(f.path) && _isArchive(f.path))
    .toList();

List<Directory> _subDirs(Directory dir) {
  final dirs = _safeList(dir)
      .whereType<Directory>()
      .where((d) => !_hidden(d.path))
      .toList();
  dirs.sort((a, b) => _naturalCompare(a.path, b.path));
  return dirs;
}

/// Images trouvées en descendant dans les sous-dossiers (borné), triées.
List<File> _deepImages(Directory dir, int maxDepth) {
  final result = <File>[];
  void walk(Directory current, int depth) {
    if (depth > maxDepth || result.length > 5000) return;
    final entries = _safeList(current);
    for (final e in entries) {
      if (e is File && !_hidden(e.path) && _isImage(e.path)) result.add(e);
    }
    if (result.isNotEmpty) return;
    for (final e in entries) {
      if (e is Directory && !_hidden(e.path)) walk(e, depth + 1);
    }
  }

  walk(dir, 0);
  result.sort((a, b) => _naturalCompare(a.path, b.path));
  return result;
}

/// Le dossier ressemble-t-il à un manga (et non à un dossier de rangement) ?
bool _looksLikeManga(Directory dir) {
  if (_archives(dir).isNotEmpty) return true;
  final subs = _subDirs(dir);
  for (final sub in subs) {
    if (_images(sub).isNotEmpty || _archives(sub).isNotEmpty) return true;
  }
  final own = _images(dir);
  if (own.length >= 3) return true;
  if (own.isNotEmpty && subs.isEmpty) return true;
  return false;
}

/// Descend dans l'arborescence jusqu'aux dossiers qui sont des mangas.
void _walkMangas(Directory dir, int depth, List<Directory> out) {
  if (depth > _maxDiscoverDepth || out.length >= _maxDiscovered) return;
  if (_looksLikeManga(dir)) {
    out.add(dir);
    return;
  }
  for (final sub in _subDirs(dir)) {
    _walkMangas(sub, depth + 1, out);
  }
}

/// Entrée de l'isolate de découverte : renvoie `[chemin, titre, couverture]`.
List<List<String>> _discoverTask(String rootPath) {
  final found = <Directory>[];
  _walkMangas(Directory(rootPath), 0, found);
  found.sort((a, b) => _naturalCompare(p.basename(a.path), p.basename(b.path)));
  return [
    for (final dir in found) [dir.path, p.basename(dir.path), _coverFor(dir) ?? ''],
  ];
}

String? _coverFor(Directory dir) {
  if (!dir.existsSync()) return null;
  final named = _findNamedCover(dir, 0);
  if (named != null) return named;
  final any = _deepImages(dir, _maxCoverDepth);
  return any.isEmpty ? null : any.first.path;
}

String? _findNamedCover(Directory dir, int depth) {
  if (depth > 2) return null;
  final named = _safeList(dir)
      .whereType<File>()
      .where(
        (f) =>
            _isImage(f.path) &&
            _coverNames.contains(p.basenameWithoutExtension(f.path).toLowerCase()),
      )
      .toList();
  if (named.isNotEmpty) {
    named.sort((a, b) => _naturalCompare(a.path, b.path));
    return named.first.path;
  }
  for (final sub in _subDirs(dir)) {
    final found = _findNamedCover(sub, depth + 1);
    if (found != null) return found;
  }
  return null;
}

/// Entrée de l'isolate des chapitres : `[dossier manga, racine]`.
List<List<String>> _collectTask(List<String> args) {
  final units = <List<String>>[];
  _collect(Directory(args[0]), args[1], 0, units);
  units.sort((a, b) => _naturalCompare(a[1], b[1]));
  return units;
}

/// Parcourt l'arborescence du manga : un dossier qui contient des images est un
/// chapitre (on ne descend pas plus bas), sinon on continue à descendre.
///
/// Si le dossier contient **à la fois** des images et des sous-dossiers de
/// chapitres, ses images sont considérées comme des couvertures et ignorées :
/// c'est ce qui évite de retrouver la couverture mélangée aux pages.
void _collect(
  Directory dir,
  String rootPath,
  int depth,
  List<List<String>> units,
) {
  if (depth > _maxChapterDepth || units.length >= _maxUnits) return;
  final entries = _safeList(dir);
  final images = <File>[];
  final dirs = <Directory>[];
  final archives = <File>[];
  for (final e in entries) {
    if (_hidden(e.path)) continue;
    if (e is File) {
      if (_isImage(e.path)) {
        images.add(e);
      } else if (_isArchive(e.path)) {
        archives.add(e);
      }
    } else if (e is Directory) {
      dirs.add(e);
    }
  }

  final hasSubUnits = archives.isNotEmpty ||
      dirs.any((d) => _images(d).isNotEmpty || _archives(d).isNotEmpty);

  if (images.isNotEmpty && !hasSubUnits) {
    units.add([dir.path, _relative(dir.path, rootPath), '${images.length}']);
    return;
  }

  for (final a in archives) {
    units.add([a.path, _relative(a.path, rootPath), '${_archivePageCount(a.path)}']);
  }
  dirs.sort((a, b) => _naturalCompare(a.path, b.path));
  for (final sub in dirs) {
    _collect(sub, rootPath, depth + 1, units);
  }
}

String _relative(String path, String rootPath) => p.equals(path, rootPath)
    ? p.basename(rootPath)
    : p.relative(path, from: rootPath);

/// « Chapitre 12 », « ch. 3 », « 04.5 » → `12`, `3`, `04.5`.
String? _chapterNumber(String relative) {
  final name = p.basenameWithoutExtension(relative);
  final match = RegExp(r'(\d+(?:[.,]\d+)?)').firstMatch(name);
  if (match == null) return null;
  return match.group(1)!.replaceAll(',', '.');
}

int _archivePageCount(String filePath) {
  try {
    final stream = InputFileStream(filePath);
    try {
      final archive = ZipDecoder().decodeStream(stream);
      return archive.files.where((f) => f.isFile && _isImage(f.name)).length;
    } finally {
      stream.closeSync();
    }
  } catch (_) {
    return 0;
  }
}

/// Petit hachage stable, utilisé pour rendre uniques les dossiers temporaires.
String _shortHash(String value) {
  var hash = 0;
  for (final unit in value.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return hash.toRadixString(16);
}
