import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/background_updates.dart';
import 'core/providers.dart';
import 'core/utils/crash_guard.dart';
import 'data/storage/storage_service.dart';

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      // Filet de sécurité : une erreur non gérée est affichée au lieu de
      // faire disparaître l'application sans explication.
      installCrashGuard();
      // On ouvre la base de données locale AVANT de lancer l'interface.
      final storage = await StorageService.init();
      // Veille périodique des chapitres (WorkManager) : ne bloque pas le
      // démarrage de l'interface.
      unawaited(initBackgroundUpdates(storage));
      runApp(
        ProviderScope(
          overrides: [storageProvider.overrideWithValue(storage)],
          child: const MangaReaderApp(),
        ),
      );
    },
    (error, stack) => reportCrash(error, stack, fatal: true),
  );
}
