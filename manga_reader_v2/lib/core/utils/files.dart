import 'dart:io';

import 'package:file_picker/file_picker.dart';

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

/// Ouvre le sélecteur de dossier natif (bibliothèque locale).
///
/// Renvoie le chemin choisi, ou `null` si l'utilisateur annule.
Future<String?> pickFolder() => FilePicker.platform.getDirectoryPath(
  dialogTitle: 'Choisir le dossier contenant les mangas',
);
