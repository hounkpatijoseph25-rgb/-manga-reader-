import "dart:convert";
import "package:hive_flutter/hive_flutter.dart";

/// Chapitres repérés par la veille et pas encore consultés.
class UpdatesRepository {
  UpdatesRepository(this._box);

  final Box<String> _box;

  static const _pendingKey = "pending";
  static const _pendingAtKey = "pendingAt";
  static const _lastRunKey = "lastRun";
  static const _lastVisitKey = "lastVisit";

  Map<String, List<String>> pending() {
    final raw = _box.get(_pendingKey);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final e in map.entries)
          e.key: (e.value as List).map((v) => "$v").toList(),
      };
    } catch (_) {
      return const {};
    }
  }

  /// Date à laquelle les premiers chapitres de chaque manga ont été repérés.
  Map<String, DateTime> detectedAt() {
    final raw = _box.get(_pendingAtKey);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final result = <String, DateTime>{};
      for (final e in map.entries) {
        final at = DateTime.tryParse("${e.value}");
        if (at != null) result[e.key] = at;
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  List<String> idsFor(String mangaKey) => pending()[mangaKey] ?? const [];

  int count() {
    var total = 0;
    for (final ids in pending().values) {
      total += ids.length;
    }
    return total;
  }

  Future<void> add(String mangaKey, List<String> ids) async {
    if (ids.isEmpty) return;
    final map = pending();
    final at = detectedAt();
    final existing = map[mangaKey] ?? const <String>[];
    final merged = <String>{...existing, ...ids};
    map[mangaKey] = merged.toList();
    // La date marque le début de la vague : les passages suivants qui
    // confirment les mêmes chapitres ne la repoussent pas.
    if (merged.length > existing.length) at.putIfAbsent(mangaKey, DateTime.now);
    await _box.putAll({
      _pendingKey: jsonEncode(map),
      _pendingAtKey: jsonEncode({
        for (final e in at.entries) e.key: e.value.toIso8601String(),
      }),
    });
  }

  /// Marque les nouveautés comme vues (le badge retombe à zéro).
  Future<void> clear() => _box.deleteAll([_pendingKey, _pendingAtKey]);

  Future<void> markRun(DateTime when) =>
      _box.put(_lastRunKey, when.toIso8601String());

  DateTime? lastRun() {
    final raw = _box.get(_lastRunKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  /// Dernière fois que l'écran « Nouveautés » a été consulté.
  Future<void> markVisited(DateTime when) =>
      _box.put(_lastVisitKey, when.toIso8601String());

  DateTime? lastVisit() {
    final raw = _box.get(_lastVisitKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  /// Se réabonne aux changements de la boîte (badge réactif).
  Stream<void> watch() => _box.watch();
}
