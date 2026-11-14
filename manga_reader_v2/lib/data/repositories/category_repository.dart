import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/category.dart';

class CategoryRepository {
  CategoryRepository(this._box);

  final Box<String> _box;

  List<Category> all() {
    final result = <Category>[];
    for (final raw in _box.values) {
      try {
        result.add(Category.fromJson(jsonDecode(raw) as Map<String, dynamic>));
      } catch (_) {
        // entrée illisible : on l'ignore
      }
    }
    result.sort((a, b) => a.order.compareTo(b.order));
    return result;
  }

  Stream<List<Category>> watch() async* {
    yield all();
    await for (final _ in _box.watch()) {
      yield all();
    }
  }

  Future<void> add(String name) {
    final existing = all();
    final category = Category(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.trim(),
      order: existing.isEmpty ? 0 : existing.last.order + 1,
    );
    return _box.put(category.id, jsonEncode(category.toJson()));
  }

  Future<void> delete(String id) => _box.delete(id);
}
