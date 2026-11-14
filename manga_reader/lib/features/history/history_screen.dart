import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/cover_image.dart';
import '../../shared/widgets/state_views.dart';
import '../details/details_screen.dart';

/// Historique de lecture : un manga par ligne, le plus récent en haut.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historique'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Tout effacer',
            onPressed: () => _confirmClear(context, ref),
          ),
        ],
      ),
      body: history.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(message: describeError(e)),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyView(
              message: 'Rien lu pour le moment.',
              icon: Icons.history,
            );
          }
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, i) {
              final entry = items[i];
              return ListTile(
                leading: SizedBox(
                  width: 46,
                  height: 66,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: CoverImage(url: entry.manga.coverUrl),
                  ),
                ),
                title: Text(
                  entry.manga.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${entry.chapterTitle} · page ${entry.page + 1}\n'
                  '${formatRelative(entry.readAt)}',
                ),
                isThreeLine: true,
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Retirer de l\'historique',
                  onPressed: () => ref
                      .read(historyRepositoryProvider)
                      .remove(entry.manga.key),
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MangaDetailsScreen(manga: entry.manga),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Effacer l'historique ?"),
        content: const Text('Ta progression de lecture est conservée.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Effacer'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(historyRepositoryProvider).clear();
  }
}
