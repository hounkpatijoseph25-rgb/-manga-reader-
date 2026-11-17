import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/background_updates.dart';
import 'core/notifications.dart';
import 'core/providers.dart';
import 'core/utils/crash_guard.dart';
import 'data/repositories/settings_repository.dart';
import 'data/storage/storage_service.dart';
import 'features/downloads/downloads_provider.dart';

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      // Filet de sécurité : une erreur non gérée est affichée au lieu de
      // faire disparaître l'application sans explication.
      installCrashGuard();
      // On ouvre la base de données locale AVANT de lancer l'interface.
      final storage = await StorageService.init();
      // Notifications : canal prêt ; l'autorisation n'est demandée que si la
      // veille des chapitres est activée dans les réglages.
      unawaited(NotificationService.init());
      if (SettingsRepository(storage.settingsBox).load().notificationsEnabled) {
        unawaited(NotificationService.requestPermission());
      }
      // Veille périodique des chapitres (WorkManager) : ne bloque pas le
      // démarrage de l'interface.
      unawaited(initBackgroundUpdates(storage));
      // Conteneur explicite : il permet de reprendre la file de téléchargement
      // juste après le lancement de l'interface.
      final container = ProviderContainer(
        overrides: [storageProvider.overrideWithValue(storage)],
      );
      // Les téléchargements de l'ancienne arborescence (dossier par source) sont
      // rangés sous le nom du manga : à faire avant l'affichage pour que la
      // Bibliothèque locale les trouve tout de suite.
      try {
        await container
            .read(downloadServiceProvider)
            .migrateLegacyLayout(
              container.read(downloadRepositoryProvider).all(),
            );
      } catch (error, stack) {
        unawaited(reportCrash(error, stack));
      }
      runApp(
        UncontrolledProviderScope(
          container: container,
          child: const MangaReaderApp(),
        ),
      );
      // Reprend les téléchargements restés en attente (coupure réseau, arrêt,
      // redémarrage du téléphone…).
      unawaited(container.read(downloadsProvider.notifier).resumePending());
    },
    (error, stack) => reportCrash(error, stack, fatal: true),
  );
}
