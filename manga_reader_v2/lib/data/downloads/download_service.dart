import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/utils/files.dart';
import '../../core/utils/network_headers.dart';
import '../models/chapter.dart';
import '../models/download_record.dart';
import '../models/manga.dart';
import '../models/manga_page.dart';
import '../sources/manga_source.dart';

/// Télécharge les pages d'un chapitre pour pouvoir le lire hors connexion.
///
/// Arborescence, un seul dossier par manga et des images en vraie extension
/// pour que la source « Bibliothèque locale » sache les relire :
///
/// ```
/// downloads/<Titre du manga>/<Chapitre>/0.jpg, 1.jpg, … + .complete
/// ```
///
/// Les images d'un même chapitre sont téléchargées **en parallèle** (par petits
/// groupes) et chaque image est **réessayée** en cas d'échec. Le dossier n'est
/// jamais supprimé au démarrage : les pages déjà écrites servent de point de
/// reprise après une coupure réseau ou un arrêt de l'application.
class DownloadService {
  DownloadService(this._dio, this._downloadsDir);

  final Dio _dio;
  final String Function() _downloadsDir;
  Directory? _root;
  String? _rootPath;

  /// Racine des téléchargements, dès qu'elle est connue (sinon `null`).
  String? get downloadsRootPath => _root?.path;

  /// Nombre d'images téléchargées simultanément dans un chapitre.
  ///
  /// On télécharge un seul chapitre à la fois. La valeur est volontairement
  /// basse : mesuré sur les CDN de MangaDex et Sushiscan, 6 connexions vont
  /// ~1,75× plus vite que 12 (au-delà, le CDN étrangle le client et le débit
  /// s'effondre).
  static const int imageConcurrency = 6;

  /// Nombre de tentatives par image.
  static const int maxAttempts = 4;

  /// Délai maximal pour une seule image (connexion + réception).
  static const Duration pageTimeout = Duration(seconds: 60);

  /// Délai maximal pour récupérer la liste des pages d'un chapitre.
  static const Duration pagesFetchTimeout = Duration(seconds: 90);

  /// Vagues de reprise après la première passe (erreurs transitoires du CDN).
  static const int retryWaves = 2;

  /// Marqueur écrit à la fin d'un chapitre : contient le nombre de pages.
  static const String _markerName = '.complete';

  static const List<String> _imageExtensions = [
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.bmp',
    '.avif',
  ];

  /// Pages du format actuel (`0.jpg`, `1.png`, …).
  static final RegExp _pagePattern = RegExp(
    r'^(\d+)\.(?:jpg|jpeg|png|webp|gif|bmp|avif)$',
    caseSensitive: false,
  );

  /// Pages de l'ancien format (`0.img`, `1.img`, …), encore relues le temps de
  /// la migration.
  static final RegExp _legacyPagePattern = RegExp(r'^(\d+)\.img$');

  Future<Directory> _rootDir() async {
    final base = await _basePath();
    final cached = _root;
    if (cached != null && _rootPath == base) return cached;
    final dir = Directory(p.join(base, 'downloads'));
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

  /// Nom de dossier lisible : seuls les caractères interdits sont remplacés, les
  /// espaces et accents sont conservés (le nom du dossier sert de titre).
  static String _safe(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'[. ]+$'), '');
    return cleaned.isEmpty ? 'sans-titre' : cleaned;
  }

  /// Ancien format (tout caractère hors `[A-Za-z0-9_-]` remplacé par `_`) :
  /// conservé uniquement pour retrouver les téléchargements déjà sur le disque.
  static String _legacySafe(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
    return cleaned.isEmpty ? '_' : cleaned;
  }

  static String _mangaFolder(Manga manga) {
    final title = manga.title.trim();
    return _safe(title.isEmpty ? manga.id : title);
  }

  Future<Directory> _mangaDir(Manga manga) async {
    final root = await _rootDir();
    return Directory(p.join(root.path, _mangaFolder(manga)));
  }

  Future<Directory> _legacyMangaDir(Manga manga) async {
    final root = await _rootDir();
    return Directory(
      p.join(root.path, _legacySafe(manga.sourceId), _legacySafe(manga.id)),
    );
  }

  /// Nom du dossier d'un chapitre téléchargé.
  String folderOf(Chapter chapter) => _safe(chapter.displayTitle);

  Future<Directory> _chapterDir(Manga manga, Chapter chapter) async {
    final dir = await _mangaDir(manga);
    return Directory(p.join(dir.path, folderOf(chapter)));
  }

  Future<Directory> _legacyChapterDir(Manga manga, Chapter chapter) async {
    final dir = await _legacyMangaDir(manga);
    return Directory(p.join(dir.path, _legacySafe(chapter.id)));
  }

  /// Dossiers des chapitres entièrement téléchargés pour ce manga.
  Future<Set<String>> downloadedFolders(Manga manga) async {
    final result = <String>{};
    for (final dir in [
      await _mangaDir(manga),
      await _legacyMangaDir(manga),
    ]) {
      if (!await dir.exists()) continue;
      await for (final entity in dir.list()) {
        if (entity is Directory &&
            await File(p.join(entity.path, _markerName)).exists()) {
          result.add(p.basename(entity.path));
        }
      }
    }
    return result;
  }

  /// Chemins des pages si le chapitre est entièrement téléchargé, sinon null.
  Future<List<String>?> localPages(Manga manga, Chapter chapter) async {
    final pages = await _chapterImages(
      await _chapterDir(manga, chapter),
      _pagePattern,
    );
    if (pages != null) return pages;
    return _chapterImages(
      await _legacyChapterDir(manga, chapter),
      _legacyPagePattern,
    );
  }

  /// Pages d'un chapitre complet, triées, ou `null` si le marqueur manque.
  Future<List<String>?> _chapterImages(Directory dir, RegExp pattern) async {
    if (!await dir.exists()) return null;
    if (!await File(p.join(dir.path, _markerName)).exists()) return null;
    final found = <int, String>{};
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final match = pattern.firstMatch(p.basename(entity.path));
      if (match == null) continue;
      found[int.parse(match.group(1)!)] = entity.path;
    }
    if (!found.containsKey(0)) return null;
    final indexes = found.keys.toList()..sort();
    return [for (final index in indexes) found[index]!];
  }

  /// Taille du dossier d'un chapitre téléchargé.
  Future<int> chapterSize(Manga manga, Chapter chapter) async {
    var total = await directorySize(await _chapterDir(manga, chapter));
    total += await directorySize(await _legacyChapterDir(manga, chapter));
    return total;
  }

  /// Télécharge un chapitre complet et renvoie le nombre de pages écrites.
  ///
  /// [concurrency] fixe le nombre d'images téléchargées simultanément.
  Future<int> downloadChapter({
    required MangaSource source,
    required Manga manga,
    required Chapter chapter,
    void Function(double progress)? onProgress,
    int concurrency = imageConcurrency,
    CancelToken? cancelToken,
  }) async {
    _throwIfCancelled(cancelToken);
    final pages = await source.fetchPages(chapter).timeout(
      pagesFetchTimeout,
      onTimeout: () => throw TimeoutException(
        'La liste des pages de « ${chapter.displayTitle} » ne répond pas.',
      ),
    );
    // `fetchPages` ne prend pas encore de CancelToken : on s'arrête dès que la
    // réponse arrive si l'utilisateur a demandé la pause entre-temps.
    _throwIfCancelled(cancelToken);
    if (pages.isEmpty) throw StateError('Aucune page à télécharger.');
    final dir = await _chapterDir(manga, chapter);
    // On NE supprime PAS le dossier : les pages déjà présentes sont conservées
    // pour reprendre un téléchargement interrompu (coupure réseau, arrêt…).
    await dir.create(recursive: true);

    final total = pages.length;
    final extensions = [for (final page in pages) _extensionFor(page)];
    var done = 0;
    var failures = <int>[];

    void report() => onProgress?.call(done / total);

    Future<void> downloadBatch(List<int> indexes, int workers) async {
      var next = 0;
      Future<void> worker() async {
        while (true) {
          if (cancelToken?.isCancelled ?? false) return;
          final cursor = next++;
          if (cursor >= indexes.length) return;
          final i = indexes[cursor];
          final target = p.join(dir.path, '$i${extensions[i]}');
          // Page déjà téléchargée et non vide → reprise, rien à refaire.
          final existing = File(target);
          if (await existing.exists() && await existing.length() > 0) {
            done++;
            report();
            continue;
          }
          try {
            await _downloadPage(
              pages[i],
              target,
              cancelToken: cancelToken,
            );
            done++;
            report();
          } catch (_) {
            // La page sera retentée dans une vague suivante ; le chapitre ne
            // sera pas marqué complet tant qu'il en manque une.
            failures.add(i);
          }
        }
      }

      await Future.wait([
        for (var w = 0; w < workers.clamp(1, 32); w++) worker(),
      ]);
    }

    await downloadBatch(
      List<int>.generate(total, (i) => i),
      concurrency,
    );
    _throwIfCancelled(cancelToken);

    // Vagues supplémentaires : un CDN qui limite le débit ou une micro-coupure
    // Wi-Fi ne doit pas condamner le chapitre entier.
    for (var wave = 0; wave < retryWaves && failures.isNotEmpty; wave++) {
      _throwIfCancelled(cancelToken);
      final retry = failures.toSet().toList()..sort();
      failures = [];
      await Future<void>.delayed(Duration(seconds: 1 + wave));
      await downloadBatch(retry, (concurrency ~/ 2).clamp(1, 8).toInt());
    }
    _throwIfCancelled(cancelToken);

    if (failures.isNotEmpty) {
      failures.sort();
      // On ne pose PAS le marqueur .complete : le chapitre sera repris plus tard.
      throw StateError(
        '${failures.length} page(s) n\'ont pas pu être téléchargée(s).',
      );
    }

    // Pages en trop (le nombre a changé) ou avec une autre extension : on les
    // retire pour que le dossier ne contienne que les pages du chapitre.
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      final match = RegExp(r'^(\d+)\.\w+$').firstMatch(name);
      if (match == null) continue;
      final index = int.parse(match.group(1)!);
      final expected = index < total ? '$index${extensions[index]}' : null;
      if (expected == null || name != expected) {
        try {
          await entity.delete();
        } catch (_) {
          // fichier verrouillé : il sera ignoré à la lecture
        }
      }
    }

    // Ce fichier prouve que tout est téléchargé (et contient le nombre de pages).
    await File(p.join(dir.path, _markerName)).writeAsString('$total');
    return total;
  }

  /// Extension de fichier d'une page : celle de l'URL si elle est connue, sinon
  /// `.jpg` (Flutter décode d'après le contenu, pas d'après l'extension).
  String _extensionFor(MangaPage page) {
    final local = page.localPath;
    if (local != null && local.isNotEmpty) {
      final ext = p.extension(local).toLowerCase();
      if (_imageExtensions.contains(ext)) return ext;
    }
    final ext = p.extension(
      Uri.tryParse(page.imageUrl)?.path ?? '',
    ).toLowerCase();
    return _imageExtensions.contains(ext) ? ext : '.jpg';
  }

  /// Déplace les chapitres de l'ancienne arborescence
  /// (`downloads/<source>/<manga>/<chapitre>/N.img`) vers la nouvelle
  /// (`downloads/<Titre>/<Chapitre>/N.jpg`).
  ///
  /// Sans effet quand tout est déjà migré, donc rejouable à chaque démarrage.
  Future<void> migrateLegacyLayout(List<DownloadRecord> records) async {
    await _rootDir();
    for (final record in records) {
      final legacy = await _legacyChapterDir(record.manga, record.chapter);
      if (!await legacy.exists()) continue;
      final target = await _chapterDir(record.manga, record.chapter);
      await target.create(recursive: true);
      await for (final entity in legacy.list()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        final match = _legacyPagePattern.firstMatch(name);
        final destination = File(
          p.join(target.path, match == null ? name : '${match.group(1)}.jpg'),
        );
        try {
          if (await destination.exists()) await destination.delete();
          await entity.rename(destination.path);
        } catch (_) {
          // fichier verrouillé : il sera retéléchargé si nécessaire
        }
      }
      try {
        await legacy.delete(recursive: true);
      } catch (_) {
        // dossier partiellement déplacé : le nettoyage repassera au lancement
      }
      final legacyManga = await _legacyMangaDir(record.manga);
      await _deleteIfEmpty(legacyManga);
      await _deleteIfEmpty(legacyManga.parent);
    }
  }

  Future<void> _deleteIfEmpty(Directory dir) async {
    try {
      if (!await dir.exists()) return;
      if (await dir.list().isEmpty) await dir.delete();
    } catch (_) {
      // dossier non vide ou verrouillé : on le laisse en place
    }
  }

  /// Télécharge une image, avec réessais et nettoyage du fichier partiel.
  Future<void> _downloadPage(
    MangaPage page,
    String target, {
    CancelToken? cancelToken,
  }) async {
    _throwIfCancelled(cancelToken);
    final local = page.localPath;
    if (local != null && local.isNotEmpty) {
      // Source locale (dossier / CBZ déjà sur l'appareil) : simple copie.
      if (local == target) return;
      try {
        await File(local).copy(target);
        _throwIfCancelled(cancelToken);
        return;
      } catch (_) {
        await _deletePartial(target);
        rethrow;
      }
    }
    if (page.imageUrl.isEmpty) throw StateError('Page sans image.');

    final headers = headersForUrl(page.imageUrl);
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      _throwIfCancelled(cancelToken);
      final cancel = CancelToken();
      if (cancelToken != null) {
        if (cancelToken.isCancelled) {
          cancel.cancel('Téléchargement annulé');
        } else {
          // Un seul token de chapitre est partagé par toutes les pages.
          // Chaque requête garde son propre token pour pouvoir être annulée
          // par le timeout sans condamner les autres pages.
          unawaited(
            cancelToken.whenCancel.then<void>((_) {
              if (!cancel.isCancelled) cancel.cancel('Téléchargement annulé');
            }),
          );
        }
      }
      try {
        // Un fichier partiel d'une tentative précédente ne doit pas être
        // concaténé à la nouvelle réponse.
        await _deletePartial(target);
        await _dio
            .download(
              page.imageUrl,
              target,
              cancelToken: cancel,
              options: Options(
                headers: headers,
                receiveTimeout: pageTimeout,
                sendTimeout: pageTimeout,
                followRedirects: true,
                validateStatus: (status) =>
                    status != null && status >= 200 && status < 300,
              ),
            )
            .timeout(
              pageTimeout,
              onTimeout: () {
                // Annule vraiment la requête : sinon elle continuerait à écrire
                // dans le fichier après le timeout.
                cancel.cancel('Délai dépassé');
                throw TimeoutException('Image trop lente : ${page.imageUrl}');
              },
            );
        final file = File(target);
        if (!await file.exists() || await file.length() == 0) {
          throw StateError('Image vide : ${page.imageUrl}');
        }
        return;
      } catch (_) {
        await _deletePartial(target);
        if (cancelToken?.isCancelled ?? false) rethrow;
        if (attempt == maxAttempts) rethrow;
        await Future<void>.delayed(
          Duration(milliseconds: 400 * attempt + Random().nextInt(250)),
        );
      }
    }
  }

  void _throwIfCancelled(CancelToken? token) {
    if (token?.isCancelled ?? false) {
      throw StateError('Téléchargement annulé.');
    }
  }

  Future<void> _deletePartial(String target) async {
    try {
      final partial = File(target);
      if (await partial.exists()) await partial.delete();
    } catch (_) {
      // Fichier déjà supprimé ou verrouillé : la tentative suivante réécrira.
    }
  }

  Future<void> deleteChapter(Manga manga, Chapter chapter) async {
    for (final dir in [
      await _chapterDir(manga, chapter),
      await _legacyChapterDir(manga, chapter),
    ]) {
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  }

  Future<int> totalSize() async => directorySize(await _rootDir());

  Future<void> clearAll() async {
    final root = await _rootDir();
    if (await root.exists()) await root.delete(recursive: true);
    await root.create(recursive: true);
  }
}
