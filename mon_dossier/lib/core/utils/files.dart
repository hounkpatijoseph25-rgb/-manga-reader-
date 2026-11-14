import 'dart:io';

/// Taille totale (en octets) des fichiers d'un dossier.
Future<int> directorySize(Directory dir) async {
  if (!await dir.exists()) return 0;
  var total = 0;
  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is File) {
      try {
        total += await entity.length();
      } catch (_) {
        // fichier supprimé entre-temps : on ignore
      }
    }
  }
  return total;
}
