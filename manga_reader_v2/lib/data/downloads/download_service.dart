import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/utils/files.dart';
import '../models/chapter.dart';
import '../models/manga.dart';
import '../sources/manga_source.dart';

/// Télécharge les pages d'un chapitre pour pouvoir le lire hors connexion.
///
/// Le dossier racine dépend du réglage [downloadsDir] (interne par défaut).
class DownloadService {
  DownloadService(this._dio, this._downloadsDir);

  final Dio _dio;
  final String Function() _downloadsDir;
  Directory? _root;
  String? _rootPath;

  Future<Directory> _rootDir() async {
    final base = await _basePath();
    final cached = _root;
    if (cached != null && _rootPath == base) return cached;
    final dir = Directory('$base/downloads');
    await dir.create(recursive: true);
    _root = dir;
    _rootPath = base;
    return dir;
  }

  Future<String> _basePath() async {
    final custom = _downloadsDir().trim();
    if (custom.isNotEmpty) return custom;
    return (await getApplicationDocumentsDirectory()).path;
  }

  String _safe(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');

  /// Nom du dossier d'un chapitre téléchargé.
  String folderOf(Chapter chapter) => _safe(chapter.id);

  Future<Directory> _mangaDir(Manga manga) async {
    final root = await _rootDir();
    return Directory(
      '${root.path}/${_safe(manga.sourceId)}/${_safe(manga.id)}',
    );
  }

  Future<Directory> _chapterDir(Manga manga, Chapter chapter) async {
    final dir = await _mangaDir(manga);
    return Directory('${dir.path}/${folderOf(chapter)}');
  }

  /// Dossiers des chapitres entièrement téléchargés pour ce manga.
  Future<Set<String>> downloadedFolders(Manga manga) async {
    final dir = await _mangaDir(manga);
    final result = <String>{};
    if (!await dir.exists()) return result;
    await for (final entity in dir.list()) {
      if (entity is Directory &&
          await File('${entity.path}/.complete').exists()) {
        result.add(entity.path.split(RegExp(r'[\\/]')).last);
      }
    }
    return result;
  }

  /// Chemins des pages si le chapitre est entièrement téléchargé, sinon null.
  Future<List<String>?> localPages(Manga manga, Chapter chapter) async {
    final dir = await _chapterDir(manga, chapter);
    final marker = File('${dir.path}/.complete');
    if (!await marker.exists()) return null;
    final count = int.tryParse(await marker.readAsString()) ?? 0;
    if (count <= 0) return null;
    final paths = [for (var i = 0; i < count; i++) '${dir.path}/$i.img'];
    // Le marqueur peut survivre à une suppression partielle : on vérifie que la
    // première page est bien là avant d'annoncer le chapitre comme lisible.
    if (!await File(paths.first).exists()) return null;
    return paths;
  }

  /// Taille du dossier d'un chapitre téléchargé.
  Future<int> chapterSize(Manga manga, Chapter chapter) async =>
      directorySize(await _chapterDir(manga, chapter));

  /// Télécharge un chapitre complet et renvoie le nombre de pages écrites.
  Future<int> downloadChapter({
    required MangaSource source,
    required Manga manga,
    required Chapter chapter,
    void Function(double progress)? onProgress,
  }) async {
    final pages = await source.fetchPages(chapter);
    if (pages.isEmpty) throw StateError('Aucune page à télécharger.');
    final dir = await _chapterDir(manga, chapter);
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    try {
      for (var i = 0; i < pages.length; i++) {
        final page = pages[i];
        final target = '${dir.path}/$i.img';
        final local = page.localPath;
        if (local != null && local.isNotEmpty) {
          // Source locale (dossier / CBZ déjà sur l'appareil) : simple copie.
          await File(local).copy(target);
        } else if (page.imageUrl.isNotEmpty) {
          await _dio.download(page.imageUrl, target);
        } else {
          throw StateError('Page ${i + 1} sans image.');
        }
        onProgress?.call((i + 1) / pages.length);
      }
      // Ce fichier prouve que tout est téléchargé (et contient le nombre de pages).
      await File('${dir.path}/.complete').writeAsString('${pages.length}');
      return pages.length;
    } catch (_) {
      if (await dir.exists()) await dir.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> deleteChapter(Manga manga, Chapter chapter) async {
    final dir = await _chapterDir(manga, chapter);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future<int> totalSize() async => directorySize(await _rootDir());

  Future<void> clearAll() async {
    final root = await _rootDir();
    if (await root.exists()) await root.delete(recursive: true);
    await root.create(recursive: true);
  }
}
