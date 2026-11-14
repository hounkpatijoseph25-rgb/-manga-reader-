import 'package:flutter/material.dart';

/// Affiche une liste de choix dans un panneau en bas de l'écran.
/// Renvoie la valeur choisie (ou null si l'utilisateur ferme le panneau).
Future<T?> showChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required List<(T, String)> options,
  required T selected,
}) {
  return showModalBottomSheet<T>(
    context: context,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(title, style: Theme.of(ctx).textTheme.titleMedium),
            ),
            for (final option in options)
              ListTile(
                title: Text(option.$2),
                trailing: option.$1 == selected
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(ctx, option.$1),
              ),
          ],
        ),
      ),
    ),
  );
}
