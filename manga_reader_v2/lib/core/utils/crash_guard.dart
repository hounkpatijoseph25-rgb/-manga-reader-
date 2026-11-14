import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Clé de navigation globale : permet d'afficher une erreur même sans contexte.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Installe le filet de sécurité : toute erreur non gérée est écrite dans un
/// fichier (`crash.log` dans les données de l'application) et montrée à
/// l'utilisateur au lieu de faire disparaître l'application sans explication.
void installCrashGuard() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    reportCrash(
      details.exception,
      details.stack ?? StackTrace.current,
      fatal: false,
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    reportCrash(error, stack, fatal: true);
    return true;
  };
}

final List<String> _reported = [];
bool _dialogOpen = false;

Future<void> reportCrash(
  Object error,
  StackTrace stack, {
  bool fatal = false,
}) async {
  final details =
      '${DateTime.now().toIso8601String()}${fatal ? ' [FATAL]' : ''}\n'
      '$error\n$stack';
  debugPrint('=== ERREUR ===\n$details');
  unawaited(_appendToLog(details));

  final summary = error.toString().split('\n').first;
  // On évite la boucle de boîtes de dialogue (une image manquante peut
  // échouer des dizaines de fois par seconde).
  if (_dialogOpen || _reported.contains(summary) || _reported.length > 15) {
    return;
  }
  _reported.add(summary);
  _showDialog(summary, details);
}

Future<void> _appendToLog(String text) async {
  try {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/crash.log');
    await file.writeAsString('$text\n\n', mode: FileMode.append, flush: true);
  } catch (_) {
    // Rien à faire : on ne veut surtout pas relancer une erreur ici.
  }
}

void _showDialog(String summary, String details) {
  final context = appNavigatorKey.currentContext;
  if (context == null) return;
  _dialogOpen = true;
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Une erreur est survenue'),
      content: SingleChildScrollView(
        child: Text(summary, style: const TextStyle(fontSize: 13)),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: details));
            if (dialogContext.mounted) Navigator.of(dialogContext).pop();
          },
          child: const Text('Copier les détails'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Fermer'),
        ),
      ],
    ),
  ).whenComplete(() => _dialogOpen = false);
}
