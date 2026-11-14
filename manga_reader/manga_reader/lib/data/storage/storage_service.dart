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
  });

  final Box<String> libraryBox;
  final Box<String> chapterIdsBox;
  final Box<String> progressBox;
  final Box<String> historyBox;
  final Box<String> categoriesBox;
  final Box<dynamic> settingsBox;

  static Future<StorageService> init() async {
    await Hive.initFlutter();
    final service = StorageService._(
      libraryBox: await Hive.openBox<String>('library'),
      chapterIdsBox: await Hive.openBox<String>('chapter_ids'),
      progressBox: await Hive.openBox<String>('progress'),
      historyBox: await Hive.openBox<String>('history'),
      categoriesBox: await Hive.openBox<String>('categories'),
      settingsBox: await Hive.openBox<dynamic>('settings'),
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
