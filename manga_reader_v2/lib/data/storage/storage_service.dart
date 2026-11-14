import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/category.dart';

/// Ouvre les "boîtes" Hive (base de données locale clé → valeur).
/// Les objets sont stockés en JSON (texte), donc aucune génération de code n'est nécessaire.
class StorageService {
  StorageService._({
    required this.libraryBox,
    required this.chapterIdsBox,
    required this.progressBox,
    required this.historyBox,
    required this.categoriesBox,
    required this.settingsBox,
    required this.downloadsBox,
    required this.chapterCacheBox,
    required this.updatesBox,
  });

  final Box<String> libraryBox;
  final Box<String> chapterIdsBox;
  final Box<String> progressBox;
  final Box<String> historyBox;
  final Box<String> categoriesBox;
  final Box<dynamic> settingsBox;

  /// Métadonnées des chapitres téléchargés (lecture hors connexion).
  final Box<String> downloadsBox;

  /// Dernière liste de chapitres connue, par manga (secours hors connexion).
  final Box<String> chapterCacheBox;

  /// Veille : nouveaux chapitres non consultés + date du dernier passage.
  final Box<String> updatesBox;

  static Future<StorageService> init() async {
    await Hive.initFlutter();
    final service = StorageService._(
      libraryBox: await Hive.openBox<String>('library'),
      chapterIdsBox: await Hive.openBox<String>('chapter_ids'),
      progressBox: await Hive.openBox<String>('progress'),
      historyBox: await Hive.openBox<String>('history'),
      categoriesBox: await Hive.openBox<String>('categories'),
      settingsBox: await Hive.openBox<dynamic>('settings'),
      downloadsBox: await Hive.openBox<String>('downloads'),
      chapterCacheBox: await Hive.openBox<String>('chapter_cache'),
      updatesBox: await Hive.openBox<String>('updates'),
    );
    await service._seedCategories();
    return service;
  }

  Future<void> _seedCategories() async {
    if (categoriesBox.isNotEmpty) return;
    const names = ['En cours', 'Terminé', 'À lire'];
    for (var i = 0; i < names.length; i++) {
      final category = Category(id: 'default_$i', name: names[i], order: i);
      await categoriesBox.put(category.id, jsonEncode(category.toJson()));
    }
  }
}
