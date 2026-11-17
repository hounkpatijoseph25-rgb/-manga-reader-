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
class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

enum _MenuAction { stopAll, clearAll }

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  final Set<String> _selected = {};
  bool _selecting = false;

  @override
  Widget build(BuildContext context) {
    final recordsAsync = ref.watch(downloadsListProvider);
    final state = ref.watch(downloadsProvider);
    final records = recordsAsync.value ?? const <DownloadRecord>[];
    final groups = _groupByManga(records);
    final totalBytes = records.fold<int>(0, (sum, r) => sum + r.bytes);

    final selectable = {...state.active.keys, ...state.queued.keys};
    final selected = _selected.where(selectable.contains).toSet();
    if (!_selecting && selected.isNotEmpty) {
      // La file a changé (chapitre terminé/arrêté) : on nettoie la sélection.
      _selected.removeWhere((key) => !selectable.contains(key));
    }

    return Scaffold(
      appBar: AppBar(
        leading: _selecting
            ? IconButton(
                tooltip: 'Annuler la sélection',
                icon: const Icon(Icons.close),
                onPressed: _cancelSelection,
              )
            : null,
        title: Text(
          _selecting
              ? '${selected.length} sélectionné${selected.length > 1 ? 's' : ''}'
              : 'Téléchargements',
        ),
        actions: _selecting
            ? [
                if (selected.isNotEmpty)
                  IconButton(
                    tooltip: 'Arrêter la sélection',
                    icon: const Icon(Icons.stop_circle_outlined),
                    onPressed: () => _confirmStopSelected(selected),
                  ),
              ]
            : [
                if (state.hasWork)
                  IconButton(
                    tooltip: state.paused ? 'Reprendre' : 'Mettre en pause',
                    icon: Icon(
                      state.paused
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                    ),
                    onPressed: () => _togglePause(state.paused),
                  ),
                if (state.hasWork || records.isNotEmpty)
                  PopupMenuButton<_MenuAction>(
                    tooltip: 'Plus d’actions',
                    onSelected: (action) {
                      switch (action) {
                        case _MenuAction.stopAll:
                          _stopAll();
                        case _MenuAction.clearAll:
                          _clearAll();
                      }
                    },
                    itemBuilder: (_) => [
                      if (state.hasWork)
                        const PopupMenuItem(
                          value: _MenuAction.stopAll,
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.stop_circle_outlined),
                            title: Text('Tout arrêter'),
                          ),
                        ),
                      if (records.isNotEmpty)
                        const PopupMenuItem(
                          value: _MenuAction.clearAll,
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.delete_sweep_outlined),
                            title: Text('Tout supprimer'),
                          ),
                        ),
                    ],
                  ),
              ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (state.paused && state.hasWork)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Icon(
                    Icons.pause_circle_outline,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Téléchargements en pause',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (state.active.isNotEmpty) ...[
            _SectionTitle('En cours (${state.active.length})'),
            for (final entry in state.active.entries)
              _ActiveTile(
                jobKey: entry.key,
                active: entry.value,
                selected: selected.contains(entry.key),
                selecting: _selecting,
                onTap: () => _toggleSelection(entry.key),
                onLongPress: () => _startSelection(entry.key),
                onStop: () => _stopOne(entry.key),
              ),
          ],
          if (state.queued.isNotEmpty) ...[
            _SectionTitle(
              state.paused
                  ? 'En pause (${state.queued.length})'
                  : 'En attente (${state.queued.length})',
              trailing: state.queued.length > 1
                  ? TextButton.icon(
                      onPressed: _sortQueue,
                      icon: const Icon(Icons.sort, size: 18),
                      label: const Text('Trier'),
                    )
                  : null,
            ),
            for (var i = 0; i < state.queued.entries.length; i++)
              Builder(
                builder: (context) {
                  final entry = state.queued.entries.elementAt(i);
                  return _QueuedTile(
                    jobKey: entry.key,
                    active: entry.value,
                    selected: selected.contains(entry.key),
                    selecting: _selecting,
                    canMoveUp: i > 0,
                    canMoveDown: i < state.queued.length - 1,
                    onMoveUp: () => ref
                        .read(downloadsProvider.notifier)
                        .moveQueued(entry.key, -1),
                    onMoveDown: () => ref
                        .read(downloadsProvider.notifier)
                        .moveQueued(entry.key, 1),
                    onTap: () => _toggleSelection(entry.key),
                    onLongPress: () => _startSelection(entry.key),
                    onStop: () => _stopOne(entry.key),
                  );
                },
              ),
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
          if (records.isEmpty && state.active.isEmpty && state.queued.isEmpty)
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

  void _startSelection(String key) {
    setState(() {
      _selecting = true;
      _selected.add(key);
    });
  }

  void _toggleSelection(String key) {
    if (!_selecting) return;
    setState(() {
      if (!_selected.remove(key)) _selected.add(key);
      if (_selected.isEmpty) _selecting = false;
    });
  }

  void _cancelSelection() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  Future<void> _sortQueue() async {
    ref.read(downloadsProvider.notifier).sortQueued();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Chapitres triés du plus petit au plus grand'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _togglePause(bool paused) async {
    final notifier = ref.read(downloadsProvider.notifier);
    if (paused) {
      await notifier.resume();
    } else {
      await notifier.pause();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          paused ? 'Téléchargements repris' : 'Téléchargements en pause',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _stopOne(String key) async {
    await ref.read(downloadsProvider.notifier).stopJobs({key});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Téléchargement arrêté'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _confirmStopSelected(Set<String> keys) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Arrêter ${keys.length} téléchargement${keys.length > 1 ? 's' : ''} ?',
        ),
        content: const Text(
          'Les chapitres sélectionnés seront retirés de la file. '
          'Les chapitres déjà terminés sont conservés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Arrêter'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(downloadsProvider.notifier).stopJobs(keys);
    if (!mounted) return;
    _cancelSelection();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Téléchargements arrêtés')));
  }

  Future<void> _stopAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Arrêter tous les téléchargements ?'),
        content: const Text(
          'Les chapitres en cours et en attente seront arrêtés. '
          'Les chapitres déjà terminés restent lisibles hors connexion.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Tout arrêter'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(downloadsProvider.notifier).stopAll();
    if (!mounted) return;
    _cancelSelection();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Téléchargements arrêtés')));
  }

  Future<void> _clearAll() async {
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
    if (!mounted) return;
    _cancelSelection();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Téléchargements supprimés')));
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
  const _ActiveTile({
    required this.jobKey,
    required this.active,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
    required this.onStop,
  });

  final String jobKey;
  final ActiveDownload active;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      selected: selected,
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
      trailing: selecting
          ? Checkbox(value: selected, onChanged: (_) => onTap())
          : IconButton(
              tooltip: 'Arrêter ce chapitre',
              icon: const Icon(Icons.stop_circle_outlined),
              onPressed: onStop,
            ),
      onTap: selecting ? onTap : null,
      onLongPress: onLongPress,
    );
  }
}

class _QueuedTile extends StatelessWidget {
  const _QueuedTile({
    required this.jobKey,
    required this.active,
    required this.selected,
    required this.selecting,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onTap,
    required this.onLongPress,
    required this.onStop,
  });

  final String jobKey;
  final ActiveDownload active;
  final bool selected;
  final bool selecting;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      selected: selected,
      contentPadding: const EdgeInsets.only(left: 16, right: 4),
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
      subtitle: Text(
        active.chapter.displayTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: selecting
          ? Checkbox(value: selected, onChanged: (_) => onTap())
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CompactIconButton(
                  tooltip: 'Monter',
                  icon: Icons.keyboard_arrow_up,
                  onPressed: canMoveUp ? onMoveUp : null,
                ),
                _CompactIconButton(
                  tooltip: 'Descendre',
                  icon: Icons.keyboard_arrow_down,
                  onPressed: canMoveDown ? onMoveDown : null,
                ),
                _CompactIconButton(
                  tooltip: 'Arrêter ce chapitre',
                  icon: Icons.stop_circle_outlined,
                  onPressed: onStop,
                ),
              ],
            ),
      onTap: selecting ? onTap : null,
      onLongPress: onLongPress,
    );
  }
}

class _CompactIconButton extends StatelessWidget {
  const _CompactIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 20),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 32, height: 38),
      onPressed: onPressed,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: Theme.of(context).colorScheme.primary),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
