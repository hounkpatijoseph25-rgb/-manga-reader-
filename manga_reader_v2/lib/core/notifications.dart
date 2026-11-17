import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notifications locales : prévient quand la veille découvre des chapitres.
///
/// Un seul canal et une seule notification à la fois (le résumé des
/// nouveautés) : une nouvelle vérification remplace la précédente.
class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _channelId = 'nouveaux-chapitres';
  static const _channelName = 'Nouveaux chapitres';
  static const _channelDescription =
      'Prévient quand des chapitres sont ajoutés aux mangas suivis.';
  static const _notificationId = 1001;

  static bool _initialized = false;

  static bool get _supported => Platform.isAndroid || Platform.isIOS;

  /// Initialise le plugin (idempotent). À appeler dans l'isolate principal
  /// **et** dans celui de la veille en arrière-plan.
  static Future<void> init() async {
    if (_initialized || !_supported) return;
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _plugin.initialize(settings: settings);
      _initialized = true;
    } catch (error) {
      debugPrint('Notifications indisponibles : $error');
    }
  }

  /// Demande l'autorisation (Android 13+). Renvoie `true` si accordée.
  static Future<bool> requestPermission() async {
    if (!_supported) return false;
    await init();
    if (!Platform.isAndroid) return true;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? true;
    } catch (error) {
      debugPrint('Autorisation notifications impossible : $error');
      return false;
    }
  }

  /// Affiche le résumé des nouveaux chapitres (remplace la notification
  /// précédente). Sans effet si [count] vaut 0.
  static Future<void> showNewChapters({
    required int count,
    required List<String> titles,
  }) async {
    if (count <= 0 || !_supported) return;
    await init();
    if (!_initialized) return;
    final body = _body(count, titles);
    try {
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          styleInformation: BigTextStyleInformation(body),
        ),
      );
      await _plugin.show(
        id: _notificationId,
        title: count == 1 ? '1 nouveau chapitre' : '$count nouveaux chapitres',
        body: body,
        notificationDetails: details,
      );
    } catch (error) {
      debugPrint('Affichage de la notification impossible : $error');
    }
  }

  static String _body(int count, List<String> titles) {
    final unique = titles.toSet().toList();
    if (unique.isEmpty) {
      return count == 1
          ? 'Un chapitre a été ajouté à votre bibliothèque.'
          : '$count chapitres ont été ajoutés à votre bibliothèque.';
    }
    if (unique.length <= 3) return unique.join(', ');
    return '${unique.take(3).join(', ')} et ${unique.length - 3} autre(s)';
  }
}
