import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/download_job.dart';

/// File d'attente des téléchargements, conservée en base locale.
///
/// Elle est écrite avant de commencer chaque chapitre et retirée une fois le
/// chapitre terminé : au prochain démarrage, tout ce qui reste est repris
/// (coupure réseau, arrêt de l'application, redémarrage du téléphone).
class DownloadQueueRepository {
  DownloadQueueRepository(this._box);

  final Box<String> _box;

  /// Chapitres en attente, dans l'ordre de la file.
  ///
  /// Les anciennes entrées n'ont pas de champ `order` : on leur attribue une
  /// position à la lecture, sans casser l'ordre dans lequel Hive les a
  /// conservées.
  List<DownloadJob> all() {
    final parsed = <({int index, DownloadJob job})>[];
    var index = 0;
    for (final raw in _box.values) {
      try {
        parsed.add((
          index: index++,
          job: DownloadJob.fromJson(jsonDecode(raw) as Map<String, dynamic>),
        ));
      } catch (_) {
        // enregistrement illisible : on l'ignore
      }
    }

    parsed.sort((a, b) {
      final ao = a.job.order;
      final bo = b.job.order;
      if (ao != null && bo != null && ao != bo) return ao.compareTo(bo);
      return a.index.compareTo(b.index);
    });

    final used = <int>{};
    var next = 0;
    final result = <DownloadJob>[];
    for (final entry in parsed) {
      var job = entry.job;
      final order = job.order;
      if (order == null || used.contains(order)) {
        while (used.contains(next)) {
          next++;
        }
        job = job.copyWith(order: next);
        used.add(next);
      } else {
        used.add(order);
      }
      result.add(job);
    }
    return result;
  }

  Future<void> addAll(Iterable<DownloadJob> jobs) async {
    final entries = {for (final job in jobs) job.key: jsonEncode(job.toJson())};
    if (entries.isEmpty) return;
    await _box.putAll(entries);
  }

  Future<void> remove(String key) => _box.delete(key);

  Future<void> clear() => _box.clear();

  /// Se réabonne aux changements de la file (compteur réactif).
  Stream<void> watch() => _box.watch();
}
