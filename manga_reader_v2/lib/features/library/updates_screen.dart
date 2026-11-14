import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/utils/format.dart';
import '../../data/models/chapter.dart';
import '../../data/models/library_entry.dart';
import '../../shared/widgets/cover_image.dart';
import '../../shared/widgets/state_views.dart';
import '../details/details_screen.dart';

/// Chapitres ajoutés aux mangas suivis depuis la dernière consultation.
///
/// La liste est figée à l'ouverture (instantané pris avant de vider le
/// badge) : marquer comme vu ne fait pas disparaître ce qui vient d'être
/// annoncé.
class UpdatesScreen extends ConsumerStatefulWidget {
  const UpdatesScreen({super.key});

  @override
  ConsumerState<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends ConsumerState<UpdatesScreen> {
  late final Map<String, List<String>> _pending;
  late final Map<String, DateTime> _detectedAt;
  late final DateTime? _previousVisit;
  late final DateTime? _lastRun;

  @override
  void initState() {
    super.initState();
    final repository = ref.read(updatesRepositoryProvider);
    _pending = repository.pending();
    _detectedAt = repository.detectedAt();
    _previousVisit = repository.lastVisit();
    _lastRun = repository.lastRun();
    // Ouvrir l'écran vaut consultation : le badge retombe tout de suite,
    // l'instantané affiché reste intact.
    repository.clear();
    repository.markVisited(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final entries =
        ref.watch(libraryEntriesProvider).value ?? const <LibraryEntry>[];
    final byKey = {for (final e in entries) e.manga.key: e};
    final cache = ref.watch(chapterCacheRepositoryProvider);
    final interval = ref.watch(
      settingsProvider.select((s) => s.updatesIntervalHours),
    );

    final rows = <_UpdateRow>[];
    for (final item in _pending.entries) {
      final entry = byKey[item.key];
      if (entry == null || item.value.isEmpty) continue;
      final chapters = cache.load(item.key);
      final byId = {for (final c in chapters) c.id: c};
      final found = [for (final id in item.value) ?byId[id]];
      if (found.isEmpty) continue;
      rows.add(
        _UpdateRow(
          entry: entry,
          chapters: found,
          addedAt: _detectedAt[item.key],
        ),
      );
    }
    rows.sort((a, b) {
      final at = a.addedAt;
      final bt = b.addedAt;
      if (at != null && bt != null && at != bt) return bt.compareTo(at);
      if (at != null) return -1;
      if (bt != null) return 1;
      return b.chapters.length.compareTo(a.chapters.length);
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Nouveautés')),
      body: rows.isEmpty
          ? EmptyView(
              icon: Icons.notifications_none,
              message: _emptyMessage(interval),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                _Summary(
                  chapters: rows.fold(0, (sum, r) => sum + r.chapters.length),
                  mangas: rows.length,
                  previousVisit: _previousVisit,
                  lastRun: _lastRun,
                ),
                for (final row in rows) _UpdateCard(row: row),
              ],
            ),
    );
  }

  String _emptyMessage(int interval) {
    final schedule = interval <= 0
        ? 'La vérification automatique est désactivée '
              '(active-la dans les réglages).'
        : 'La vérification tourne toutes les $interval heures et au lancement.';
    final last = _lastRun == null
        ? ''
        : '\nDernière vérification : ${formatRelative(_lastRun).toLowerCase()}.';
    return 'Aucun nouveau chapitre depuis ta dernière visite.\n$schedule$last';
  }
}

class _UpdateRow {
  _UpdateRow({
    required this.entry,
    required this.chapters,
    required this.addedAt,
  });

  final LibraryEntry entry;
  final List<Chapter> chapters;
  final DateTime? addedAt;
}

/// En-tête : combien de chapitres, depuis quand, et quand la veille a tourné.
class _Summary extends StatelessWidget {
  const _Summary({
    required this.chapters,
    required this.mangas,
    required this.previousVisit,
    required this.lastRun,
  });

  final int chapters;
  final int mangas;
  final DateTime? previousVisit;
  final DateTime? lastRun;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visit = previousVisit;
    final run = lastRun;
    final since = visit == null
        ? 'Depuis la mise en place de la veille'
        : 'Depuis ta dernière visite '
              '(${formatRelative(visit).toLowerCase()})';
    final checked = run == null
        ? ''
        : ' · Vérifié ${formatRelative(run).toLowerCase()}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$chapters nouveau${chapters > 1 ? 'x' : ''} '
            'chapitre${chapters > 1 ? 's' : ''} dans '
            '$mangas manga${mangas > 1 ? 's' : ''}',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            '$since$checked',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _UpdateCard extends StatelessWidget {
  const _UpdateCard({required this.row});

  final _UpdateRow row;

  @override
  Widget build(BuildContext context) {
    final manga = row.entry.manga;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sorted = [...row.chapters]
      ..sort((a, b) => b.numberValue.compareTo(a.numberValue));

    return Card(
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MangaDetailsScreen(manga: manga),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 54,
                  height: 78,
                  child: CoverImage(url: manga.coverUrl),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      manga.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          '${row.chapters.length} nouveau'
                          '${row.chapters.length > 1 ? 'x' : ''} chapitre'
                          '${row.chapters.length > 1 ? 's' : ''}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (row.addedAt != null) ...[
                          Text(
                            ' · ${formatRelative(row.addedAt!).toLowerCase()}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    for (final chapter in sorted) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 4, right: 6),
                            child: Icon(
                              Icons.fiber_manual_record,
                              size: 7,
                              color: scheme.primary,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              chapter.displayTitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
