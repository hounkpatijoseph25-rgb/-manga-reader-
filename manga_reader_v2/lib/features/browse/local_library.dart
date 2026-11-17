import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/providers.dart';
import '../../core/utils/files.dart';
import '../../core/utils/storage_access.dart';
import '../../data/models/manga.dart';
import '../../data/sources/local_source.dart';
import '../details/details_providers.dart';
import 'browse_providers.dart';

/// Vérifie l'accès « tous les fichiers » et propose de l'accorder.
///
/// Renvoie `true` seulement quand l'application peut réellement lire le disque.
Future<bool> ensureLocalAccess(BuildContext context) async {
  if (await StorageAccess.hasAllFilesAccess()) return true;
  if (!context.mounted) return false;

  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Accès aux fichiers requis'),
      content: const Text(
        'Pour lire les mangas et webtoons déjà présents sur ton téléphone, '
        'Android doit autoriser l\'application à accéder aux fichiers.\n\n'
        'Sur l\'écran qui va s\'ouvrir, active « Autoriser la gestion de tous '
        'les fichiers », puis reviens ici.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Plus tard'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Autoriser'),
        ),
      ],
    ),
  );
  if (accepted != true) return false;

  await StorageAccess.requestAllFilesAccess();
  // On attend que l'utilisateur accorde la permission puis revienne dans l'app.
  for (var i = 0; i < 120; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (await StorageAccess.hasAllFilesAccess()) return true;
  }
  return false;
}

/// Choisit le dossier racine de la bibliothèque locale (permission incluse).
Future<void> pickLocalRoot(BuildContext context, WidgetRef ref) async {
  final granted = await ensureLocalAccess(context);
  if (!granted) {
    if (context.mounted) {
      _snack(
        context,
        'Sans « Accès à tous les fichiers », le dossier ne pourra pas être lu.',
      );
    }
    return;
  }

  final path = await pickFolder();
  if (path == null) return;

  ref.read(settingsProvider.notifier).setLocalRoot(path);
  ref.invalidate(localSourceProvider);
  _reloadLocalCatalog(ref);
  if (!context.mounted) return;

  if (!StorageAccess.canRead(path)) {
    _snack(
      context,
      'Dossier illisible. Autorise « Accès à tous les fichiers » puis réessaie.',
    );
  } else {
    _snack(context, 'Dossier local enregistré');
  }
}

/// Oublie le dossier importé.
void forgetLocalRoot(BuildContext context, WidgetRef ref) {
  ref.read(settingsProvider.notifier).setLocalRoot('');
  ref.invalidate(localSourceProvider);
  _reloadLocalCatalog(ref);
  _snack(context, 'Dossier local oublié');
}

/// Force le catalogue de la bibliothèque locale à se recharger quand le dossier
/// change, pour que les mangas/webtoons apparaissent sans autre action.
void _reloadLocalCatalog(WidgetRef ref) {
  if (ref.read(catalogProvider).sourceId == 'local') {
    ref.read(catalogProvider.notifier).refresh();
  }
}

/// Choix de l'image de présentation d'un manga/webtoon local.
Future<void> showLocalCoverSheet(
  BuildContext context,
  WidgetRef ref,
  Manga manga,
) async {
  final candidates = LocalMangaSource.coverCandidates(manga.id);
  final current = ref.read(settingsProvider).localCovers[manga.id];
  final theme = Theme.of(context);

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      void apply(String coverPath) {
        ref.read(settingsProvider.notifier).setLocalCover(manga.id, coverPath);
        Navigator.of(sheetContext).pop();
        _refreshCover(ref, manga);
      }

      void reset() {
        ref.read(settingsProvider.notifier).clearLocalCover(manga.id);
        Navigator.of(sheetContext).pop();
        _refreshCover(ref, manga);
      }

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Image de présentation',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 2),
              Text(manga.title, style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              if (candidates.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Aucune image trouvée dans ce dossier.'),
                )
              else
                SizedBox(
                  height: 250,
                  child: GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 92,
                          childAspectRatio: 0.68,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                    itemCount: candidates.length,
                    itemBuilder: (_, index) {
                      final path = candidates[index];
                      return InkWell(
                        onTap: () => apply(path),
                        child: Container(
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              width: 3,
                              color: current == path
                                  ? theme.colorScheme.primary
                                  : Colors.transparent,
                            ),
                          ),
                          child: Image.file(
                            File(path),
                            fit: BoxFit.cover,
                            cacheWidth: 180,
                            errorBuilder: (_, _, _) => const Icon(
                              Icons.broken_image_outlined,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await FilePicker.platform.pickFiles(
                          type: FileType.image,
                        );
                        final source = picked?.files.single.path;
                        if (source == null) return;
                        apply(await _persistCover(source));
                      },
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Du téléphone'),
                    ),
                  ),
                  if (current != null) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextButton.icon(
                        onPressed: reset,
                        icon: const Icon(Icons.restart_alt),
                        label: const Text('Automatique'),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Recalcule la couverture d'un manga local et la propage :
/// la fiche se rafraîchit **et** l'entrée de bibliothèque est mise à jour
/// (sinon la carte de la bibliothèque continue d'afficher l'ancienne image).
Future<void> _refreshCover(WidgetRef ref, Manga manga) async {
  ref.invalidate(mangaDetailsProvider(manga));
  try {
    final updated = await ref.read(localSourceProvider).fetchMangaDetails(manga);
    await ref.read(libraryRepositoryProvider).updateManga(updated);
  } catch (_) {
    // Le choix reste enregistré dans les réglages : la fiche le montrera.
  }
}

/// Copie l'image choisie dans les données de l'application pour qu'elle
/// survive même si le fichier d'origine est déplacé.
Future<String> _persistCover(String sourcePath) async {
  try {
    final dir = Directory(
      p.join((await getApplicationSupportDirectory()).path, 'covers'),
    );
    await dir.create(recursive: true);
    final ext = p.extension(sourcePath).toLowerCase();
    final target = File(
      p.join(dir.path, '${DateTime.now().microsecondsSinceEpoch}$ext'),
    );
    return (await File(sourcePath).copy(target.path)).path;
  } catch (_) {
    return sourcePath;
  }
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
