import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import '../data/repositories/settings_repository.dart';
import '../data/storage/storage_service.dart';
import '../features/library/library_updater.dart';
import 'providers.dart';
import 'utils/crash_guard.dart';

/// Veille des nouveaux chapitres en arrière-plan (WorkManager).
///
/// La tâche périodique relit les chapitres des mangas suivis même quand
/// l'application est fermée : les nouveautés sont enregistrées dans la boîte
/// Hive `updates`, donc le badge est déjà à jour au prochain lancement.
const _taskName = 'library-updates';
const _taskUnique = 'library-updates-periodic';

/// WorkManager n'a d'implémentation que sur Android (et iOS via BGTaskScheduler).
bool get _supported => Platform.isAndroid || Platform.isIOS;

/// Point d'entrée exécuté dans un isolate séparé par le système.
///
/// Il ne partage rien avec l'isolate principal : on rouvre la base et on
/// construit un conteneur Riverpod jetable le temps de la vérification.
@pragma('vm:entry-point')
void updatesCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    ProviderContainer? container;
    try {
      final storage = await StorageService.init();
      container = ProviderContainer(
        overrides: [storageProvider.overrideWithValue(storage)],
      );
      final report = await container
          .read(libraryUpdaterProvider.notifier)
          .refresh();
      debugPrint(
        'Veille hors application : ${report.newChapters} nouveau(x) '
        'chapitre(s), ${report.checked} manga(s) vérifié(s).',
      );
      return true;
    } catch (error, stack) {
      // Pas de dialogue possible ici (l'interface n'existe pas) : le journal
      // de plantage reste consultable au prochain lancement.
      await reportCrash(error, stack);
      return false;
    } finally {
      container?.dispose();
    }
  });
}

/// À appeler une fois au démarrage : branche le rappel puis (re)planifie la
/// vérification selon le réglage enregistré.
Future<void> initBackgroundUpdates(StorageService storage) async {
  if (!_supported) return;
  try {
    await Workmanager().initialize(updatesCallbackDispatcher);
    final hours = SettingsRepository(
      storage.settingsBox,
    ).load().updatesIntervalHours;
    await applyUpdatesSchedule(hours);
  } catch (error) {
    debugPrint('WorkManager indisponible : $error');
  }
}

/// (Re)planifie la veille toutes les [hours] heures (`0` = désactivée).
///
/// L'ancienne planification est toujours annulée : changer la fréquence ne
/// laisse pas deux tâches tourner en parallèle.
Future<void> applyUpdatesSchedule(int hours) async {
  if (!_supported) return;
  try {
    await Workmanager().cancelByUniqueName(_taskUnique);
    if (hours <= 0) return;
    await Workmanager().registerPeriodicTask(
      _taskUnique,
      _taskName,
      frequency: Duration(hours: hours),
      initialDelay: Duration(hours: hours),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );
  } catch (error) {
    debugPrint('Planification de la veille impossible : $error');
  }
}
