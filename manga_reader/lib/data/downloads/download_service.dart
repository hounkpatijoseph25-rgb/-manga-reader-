import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/utils/files.dart';
import '../models/chapter.dart';
import '../models/manga.dart';
import '../sources/manga_source.dart';

/// Télécharge les pages d'un chapitre dans le stockage de l'application
/// pour pouvoir le lire hors connexion.
class DownloadService {
  DownloadService(this._dio);

  final Dio _dio;
  Directory? _root;

  Future<Directory> _rootDir() async {
    final cached = _root;
    if (cached != null) return cached;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/downloads');
    await dir.create(recursive: true);
    _root = dir;
    return dir;
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
    return [for (var i = 0; i < count; i++) '${dir.path}/$i.img'];
  }

  Future<void> downloadChapter({
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
        await _dio.download(pages[i].imageUrl, '${dir.path}/$i.img');
        onProgress?.call((i + 1) / pages.length);
      }
      // Ce fichier prouve que tout est téléchargé (et contient le nombre de pages).
      await File('${dir.path}/.complete').writeAsString('${pages.length}');
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
