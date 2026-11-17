import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Maintient les téléchargements en cours quand l'application n'est plus au
/// premier plan.
///
/// La file de téléchargement vit dans l'isolate principal (Riverpod) ; un
/// service de premier plan Android garde le processus en vie et affiche une
/// notification de progression. Sans lui, Android peut geler puis tuer
/// l'application dès qu'elle passe en arrière-plan.
class BackgroundDownloads {
  BackgroundDownloads._();

  static const _notificationId = 1001;

  static bool _ready = false;
  static bool _running = false;

  /// Sérialise `start`/`stop` : un arrêt demandé juste après un démarrage ne
  /// doit pas laisser le service tourner, et inversement.
  static Future<void> _lifecycle = Future<void>.value();

  static bool get supported => Platform.isAndroid || Platform.isIOS;

  static Future<void> _serialized(Future<void> Function() action) {
    final next = _lifecycle.then((_) => action());
    _lifecycle = next.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return next;
  }

  /// Démarre le service (ou met à jour sa notification s'il tourne déjà).
  static Future<void> start({
    required String text,
    String title = 'Téléchargements',
  }) {
    if (!supported) return Future<void>.value();
    _init();
    return _serialized(() => _startNow(text: text, title: title));
  }

  static Future<void> _startNow({
    required String text,
    required String title,
  }) async {
    try {
      if (!_running) {
        if (!await FlutterForegroundTask.isRunningService) {
          await _requestNotificationPermission();
          await _requestBatteryOptimizationExemption();
          final result = await FlutterForegroundTask.startService(
            serviceId: _notificationId,
            serviceTypes: const [ForegroundServiceTypes.dataSync],
            notificationTitle: title,
            notificationText: text,
            callback: backgroundDownloadsCallback,
          );
          if (result is ServiceRequestFailure) {
            debugPrint('Service de téléchargement : ${result.error}');
            return;
          }
        }
        _running = true;
      }
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: text,
      );
    } catch (error) {
      debugPrint('Service de téléchargement indisponible : $error');
    }
  }

  /// Met à jour la progression affichée dans la notification.
  static Future<void> update({
    required String text,
    String? title,
  }) async {
    if (!supported || !_running) return;
    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: text,
      );
    } catch (error) {
      debugPrint('Mise à jour de la notification impossible : $error');
    }
  }

  /// Arrête le service une fois la file vidée.
  ///
  /// [shouldStop] est réévalué au moment où l'arrêt s'exécute : si un nouveau
  /// téléchargement a été ajouté entre-temps, le service reste en vie.
  static Future<void> stop({bool Function()? shouldStop}) {
    if (!supported) return Future<void>.value();
    return _serialized(() async {
      if (shouldStop != null && !shouldStop()) return;
      _running = false;
      try {
        if (await FlutterForegroundTask.isRunningService) {
          await FlutterForegroundTask.stopService();
        }
      } catch (error) {
        debugPrint('Arrêt du service de téléchargement impossible : $error');
      }
    });
  }

  static void _init() {
    if (_ready) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'downloads',
        channelName: 'Téléchargements',
        channelDescription:
            'Progression des chapitres en cours de téléchargement.',
        onlyAlertOnce: true,
        showWhen: false,
        visibility: NotificationVisibility.VISIBILITY_PRIVATE,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // Aucune tâche répétitive : le service ne sert qu'à garder le
        // processus en vie. La progression vient de l'isolate principal.
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
        // Redémarrer le service sans l'isolate principal ne servirait à rien :
        // la file de téléchargement vit dans l'application.
        allowAutoRestart: false,
        // Retirer l'app des récents détruit l'activité Flutter : le service
        // n'aurait plus de file à faire avancer, on l'arrête avec la tâche.
        stopWithTask: true,
      ),
    );
    _ready = true;
  }

  static Future<void> _requestNotificationPermission() async {
    if (!Platform.isAndroid) return;
    try {
      final permission =
          await FlutterForegroundTask.checkNotificationPermission();
      if (permission != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
    } catch (error) {
      // Refus ou absence d'activité : le service peut quand même tourner.
      debugPrint('Permission de notification : $error');
    }
  }

  /// Demande une seule fois à Android d'exempter l'application de
  /// l'optimisation de batterie : sans cela, certains constructeurs tuent le
  /// service dès que l'écran est verrouillé.
  static Future<void> _requestBatteryOptimizationExemption() async {
    if (!Platform.isAndroid) return;
    try {
      if (await FlutterForegroundTask.isIgnoringBatteryOptimizations) return;
      final asked =
          await FlutterForegroundTask.getData<bool>(key: 'battery-asked') ??
          false;
      if (asked) return;
      await FlutterForegroundTask.saveData(key: 'battery-asked', value: true);
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    } catch (error) {
      debugPrint('Exemption batterie : $error');
    }
  }
}

/// Le service exige un gestionnaire de tâche, même sans travail propre :
/// les téléchargements restent pilotés par l'isolate principal.
@pragma('vm:entry-point')
void backgroundDownloadsCallback() {
  FlutterForegroundTask.setTaskHandler(_KeepAliveTaskHandler());
}

class _KeepAliveTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
