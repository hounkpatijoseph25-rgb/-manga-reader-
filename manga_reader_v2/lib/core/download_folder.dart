import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../core/utils/files.dart';

/// S'assure qu'un emplacement de téléchargement est choisi.
/// Retourne `true` si on peut lancer le téléchargement.
Future<bool> ensureDownloadsLocation(
  BuildContext context,
  WidgetRef ref,
) async {
  final settings = ref.read(settingsProvider);
  if (settings.downloadsDirMode != 'unset') return true;

  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Dossier de téléchargements'),
      content: const Text(
        'Choisis où enregistrer les chapitres téléchargés. '
        'Tu pourras modifier ce choix plus tard dans les paramètres.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'cancel'),
          child: const Text('Annuler'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'internal'),
          child: const Text('Dossier interne'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, 'custom'),
          child: const Text('Choisir un dossier'),
        ),
      ],
    ),
  );

  if (choice == null || choice == 'cancel' || !context.mounted) return false;
  if (choice == 'internal') {
    ref.read(settingsProvider.notifier).setDownloadsDirMode('internal');
    return true;
  }
  if (choice == 'custom') {
    final path = await pickFolder();
    if (path == null || !context.mounted) return false;
    ref.read(settingsProvider.notifier).setDownloadsDir(path);
    return true;
  }
  return false;
}
