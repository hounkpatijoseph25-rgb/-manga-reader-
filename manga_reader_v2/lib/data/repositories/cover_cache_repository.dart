import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Copie locale des couvertures de la bibliothèque.
///
/// Le cache d'images de Flutter peut être vidé à tout moment : on garde donc
/// une copie sur l'appareil pour que les couvertures restent visibles même
/// sans connexion.
class CoverCacheRepository {
  CoverCacheRepository(this._dio);

  final Dio _dio;

  Directory? _dir;
  Map<String, String> _index = {};
  bool _loaded = false;
  final Set<String> _running = {};

  /// Index courant : `url → chemin du fichier`.
  Map<String, String> get index => _index;

  Future<Directory> _coverDir() async {
    final cached = _dir;
    if (cached != null) return cached;
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'covers'));
    await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  /// Lit l'index sur le disque (une seule fois par lancement).
  Future<Map<String, String>> load() async {
    if (_loaded) return _index;
    _loaded = true;
    try {
      final dir = await _coverDir();
      final file = File(p.join(dir.path, 'index.json'));
      if (await file.exists()) {
        final raw = jsonDecode(await file.readAsString());
        if (raw is Map) {
          final fromDisk = {
            for (final e in raw.entries) '${e.key}': '${e.value}',
          };
          // On conserve ce qui a pu être ajouté entre-temps.
          _index = {...fromDisk, ..._index};
        }
      }
      // Fichiers supprimés entre-temps : on nettoie l'index.
      _index.removeWhere((_, path) => !File(path).existsSync());
    } catch (_) {
      _index = {};
    }
    return _index;
  }

  /// Chemin local déjà téléchargé pour cette URL, sinon `null`.
  String? localFor(String url) {
    final path = _index[url];
    if (path == null) return null;
    return File(path).existsSync() ? path : null;
  }

  /// Télécharge la couverture si nécessaire et renvoie son chemin local.
  Future<String?> ensure(String url, {Map<String, dynamic>? headers}) async {
    final existing = localFor(url);
    if (existing != null) return existing;
    if (_running.contains(url)) return null;
    _running.add(url);
    try {
      final dir = await _coverDir();
      final target = p.join(dir.path, '${_hash(url)}.img');
      await _dio.download(
        url,
        target,
        options: Options(headers: headers),
      );
      _index[url] = target;
      await _saveIndex();
      return target;
    } catch (_) {
      // Hors connexion : on réessaiera au prochain rafraîchissement.
      return null;
    } finally {
      _running.remove(url);
    }
  }

  Future<void> _saveIndex() async {
    try {
      final dir = await _coverDir();
      await File(
        p.join(dir.path, 'index.json'),
      ).writeAsString(jsonEncode(_index), flush: true);
    } catch (_) {
      // L'index sera reconstruit au pire : pas grave.
    }
  }

  static String _hash(String value) {
    var hash = 0;
    for (final unit in value.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash.toRadixString(16);
  }
}
