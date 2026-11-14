import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/utils/format.dart';
import '../../data/models/chapter.dart';
import '../../data/models/download_record.dart';
import '../../data/models/manga.dart';
import '../../shared/widgets/cover_image.dart';
import '../../shared/widgets/state_views.dart';
import '../reader/reader_screen.dart';
import '../settings/storage_info_provider.dart';
import 'downloads_provider.dart';

/// Écran de gestion des téléchargements : ce qui est en cours et ce qui est
/// déjà lisible hors connexion.
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordsAsync = ref.watch(downloadsListProvider);
    final state = ref.watch(downloadsProvider);
    final records = recordsAsync.value ?? const <DownloadRecord>[];
    final groups = _groupByManga(records);
    final totalBytes = records.fold<int>(0, (sum, r) => sum + r.bytes);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Téléchargements'),
        actions: [
          if (records.isNotEmpty || state.active.isNotEmpty)
            IconButton(
              tooltip: 'Tout supprimer',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () => _clearAll(context, ref),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (state.active.isNotEmpty) ...[
            _SectionTitle('En cours (${state.active.length})'),
            for (final entry in state.active.entries)
              _ActiveTile(active: entry.value),
          ],
          if (state.failed.isNotEmpty) ...[
            _SectionTitle('Échecs (${state.failed.length})'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Ces chapitres n\'ont pas pu être téléchargés. '
                'Ouvre la fiche du manga pour réessayer.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
          if (records.isEmpty && state.active.isEmpty)
            const SizedBox(
              height: 320,
              child: EmptyView(
                icon: Icons.download_for_offline_outlined,
                message:
                    'Aucun chapitre téléchargé.\n'
                    'Ouvre un manga et appuie sur « Télécharger » pour '
                    'le lire sans connexion.',
              ),
            )
          else if (records.isNotEmpty) ...[
            _SectionTitle('Hors connexion · ${formatBytes(totalBytes)}'),
            for (final group in groups) _MangaDownloads(group: group),
          ],
        ],
      ),
    );
  }

  List<_DownloadGroup> _groupByManga(List<DownloadRecord> records) {
    final map = <String, _DownloadGroup>{};
    for (final record in records) {
      final group = map.putIfAbsent(
        record.manga.key,
        () => _DownloadGroup(record.manga),
      );
      group.records.add(record);
    }
    for (final group in map.values) {
      group.records.sort(
        (a, b) => a.chapter.numberValue.compareTo(b.chapter.numberValue),
      );
    }
    return map.values.toList();
  }

  Future<void> _clearAll(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer tous les téléchargements ?'),
        content: const Text(
          'Les chapitres ne seront plus lisibles hors connexion.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(downloadsProvider.notifier).clearAll();
    ref.invalidate(storageInfoProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Téléchargements supprimés')),
      );
    }
  }
}

class _DownloadGroup {
  _DownloadGroup(this.manga);

  final Manga manga;
  final List<DownloadRecord> records = [];

  int get bytes => records.fold<int>(0, (sum, r) => sum + r.bytes);
}

class _MangaDownloads extends ConsumerWidget {
  const _MangaDownloads({required this.group});

  final _DownloadGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final chapters = [for (final r in group.records) r.chapter];

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: SizedBox(
          width: 44,
          height: 62,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: CoverImage(url: group.manga.coverUrl),
          ),
        ),
        title: Text(
          group.manga.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${chapters.length} chapitre${chapters.length > 1 ? 's' : ''} · '
          '${formatBytes(group.bytes)}',
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => _openReader(context, chapters, 0),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Lire hors connexion'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Supprimer ce manga',
                  icon: Icon(Icons.delete_outline, color: scheme.error),
                  onPressed: () => _removeManga(context, ref),
                ),
              ],
            ),
          ),
          for (var i = 0; i < group.records.length; i++)
            ListTile(
              dense: true,
              leading: const Icon(Icons.picture_as_pdf_outlined, size: 20),
              title: Text(group.records[i].chapter.displayTitle),
              subtitle: Text(formatBytes(group.records[i].bytes)),
              trailing: IconButton(
                tooltip: 'Supprimer',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  await ref
                      .read(downloadsProvider.notifier)
                      .remove(group.manga, group.records[i].chapter);
                  ref.invalidate(storageInfoProvider);
                },
              ),
              onTap: () => _openReader(context, chapters, i),
            ),
        ],
      ),
    );
  }

  void _openReader(BuildContext context, List<Chapter> chapters, int index) {
    if (chapters.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReaderScreen(
          manga: group.manga,
          chapters: chapters,
          initialIndex: index,
        ),
      ),
    );
  }

  Future<void> _removeManga(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Supprimer ${group.manga.title} ?'),
        content: Text(
          '${group.records.length} chapitre(s) seront supprimés de '
          "l'appareil.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final notifier = ref.read(downloadsProvider.notifier);
    for (final record in List<DownloadRecord>.of(group.records)) {
      await notifier.remove(record.manga, record.chapter);
    }
    ref.invalidate(storageInfoProvider);
  }
}

class _ActiveTile extends StatelessWidget {
  const _ActiveTile({required this.active});

  final ActiveDownload active;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: SizedBox(
        width: 44,
        height: 62,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: CoverImage(url: active.manga.coverUrl),
        ),
      ),
      title: Text(
        active.manga.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            active.chapter.displayTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: active.progress > 0 ? active.progress : null,
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
