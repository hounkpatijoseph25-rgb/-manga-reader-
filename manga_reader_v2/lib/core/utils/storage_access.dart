import 'dart:io';

import 'package:flutter/services.dart';

/// Accès « tous les fichiers » sur Android.
///
/// Sans cette permission, l'application ne peut pas lire un dossier choisi par
/// l'utilisateur (mangas/webtoons déjà installés sur le téléphone) : `dart:io`
/// ne voit alors rien et la bibliothèque locale reste vide.
class StorageAccess {
  StorageAccess._();

  static const MethodChannel _channel = MethodChannel('manga_reader/storage');

  /// `true` si l'application peut lire n'importe quel fichier du téléphone.
  static Future<bool> hasAllFilesAccess() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('hasAllFilesAccess') ?? false;
    } on MissingPluginException {
      return true; // canal absent : on ne bloque pas l'utilisateur
    } on PlatformException {
      return false;
    }
  }

  /// Ouvre l'écran système « Accès à tous les fichiers ».
  static Future<void> requestAllFilesAccess() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('requestAllFilesAccess');
    } on MissingPluginException {
      // ignoré
    } on PlatformException {
      // ignoré
    }
  }

  /// Vérifie qu'un dossier existe et qu'on peut le parcourir.
  static bool canRead(String path) {
    try {
      final dir = Directory(path);
      if (!dir.existsSync()) return false;
      dir.listSync().take(1).toList();
      return true;
    } catch (_) {
      return false;
    }
  }
}
