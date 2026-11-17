import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../data/storage/storage_service.dart';

/// Sauvegarde et restauration de la base locale (bibliothèque, progression,
/// historique, catégories, réglages) dans un unique fichier JSON.
///
/// Les boîtes Hive stockent du texte JSON, on les recopie donc telles quelles :
/// aucune conversion objet n'est nécessaire et le format reste lisible.
class BackupService {
  BackupService(this._storage);

  final StorageService _storage;

  /// Version du format de sauvegarde (à incrémenter si le schéma change).
  static const int formatVersion = 1;

  /// Construit la sauvegarde complète en mémoire.
  Map<String, dynamic> build() {
    return {
      'app': 'manga_reader',
      'formatVersion': formatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'data': {
        'library': _dumpString(_storage.libraryBox),
        'chapterIds': _dumpString(_storage.chapterIdsBox),
        'progress': _dumpString(_storage.progressBox),
        'history': _dumpString(_storage.historyBox),
        'categories': _dumpString(_storage.categoriesBox),
        'updates': _dumpString(_storage.updatesBox),
        'settings': Map<String, dynamic>.from(_storage.settingsBox.toMap()),
      },
    };
  }

  /// Sérialise la sauvegarde en JSON indenté (lisible par un humain).
  String encode() => const JsonEncoder.withIndent('  ').convert(build());

  /// Restaure une sauvegarde.
  ///
  /// Si [replace] est vrai (par défaut), les boîtes sont vidées avant écriture ;
  /// sinon les données du fichier sont fusionnées avec l'existant.
  Future<void> restore(Map<String, dynamic> json, {bool replace = true}) async {
    final data = json['data'];
    if (data is! Map) {
      throw const FormatException('Fichier de sauvegarde invalide');
    }
    await _restoreString(_storage.libraryBox, data['library'], replace);
    await _restoreString(_storage.chapterIdsBox, data['chapterIds'], replace);
    await _restoreString(_storage.progressBox, data['progress'], replace);
    await _restoreString(_storage.historyBox, data['history'], replace);
    await _restoreString(_storage.categoriesBox, data['categories'], replace);
    await _restoreString(_storage.updatesBox, data['updates'], replace);
    await _restoreSettings(data['settings'], replace);
  }

  static Map<String, String> _dumpString(Box<String> box) => {
    for (final key in box.keys)
      if (box.get(key) != null) '$key': box.get(key)!,
  };

  static Future<void> _restoreString(
    Box<String> box,
    Object? dump,
    bool replace,
  ) async {
    if (dump is! Map) return;
    if (replace) await box.clear();
    for (final entry in dump.entries) {
      final value = entry.value;
      if (value is String) await box.put('${entry.key}', value);
    }
  }

  Future<void> _restoreSettings(Object? dump, bool replace) async {
    if (dump is! Map) return;
    if (replace) await _storage.settingsBox.clear();
    for (final entry in dump.entries) {
      await _storage.settingsBox.put('${entry.key}', entry.value);
    }
  }
}
