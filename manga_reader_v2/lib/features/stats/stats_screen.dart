import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/utils/format.dart';
import '../../data/models/download_record.dart';
import '../../data/models/history_entry.dart';
import '../../data/models/library_entry.dart';
import '../../data/models/manga.dart';
import '../../data/models/manga_progress.dart';
import '../../shared/widgets/state_views.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(libraryEntriesProvider);
    final entries = entriesAsync.value ?? const <LibraryEntry>[];
    final progress =
        ref.watch(allProgressProvider).value ?? const <String, MangaProgress>{};
    final downloads =
        ref.watch(downloadsListProvider).value ?? const <DownloadRecord>[];
    final history = ref.watch(historyProvider).value ?? const <HistoryEntry>[];
    final categoryCount = ref.watch(categoriesProvider).value?.length ?? 0;

    if (entriesAsync.isLoading && entries.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Statistiques')),
        body: const LoadingView(),
      );
    }

    var followedChapters = 0;
    var ongoing = 0;
    var completed = 0;
    var otherStatus = 0;
    for (final entry in entries) {
      followedChapters += entry.chapterCount;
      switch (entry.manga.status) {
        case MangaStatus.ongoing:
          ongoing++;
        case MangaStatus.completed:
          completed++;
        case MangaStatus.hiatus:
        case MangaStatus.cancelled:
        case MangaStatus.unknown:
          otherStatus++;
      }
    }

    var readChapters = 0;
    var bookmarks = 0;
    for (final value in progress.values) {
      readChapters += value.readChapterIds.length;
      bookmarks += value.bookmarkedChapterIds.length;
    }

    var downloadedPages = 0;
    var downloadedBytes = 0;
    for (final record in downloads) {
      downloadedPages += record.pageCount;
      downloadedBytes += record.bytes;
    }

    DateTime? lastRead;
    for (final entry in history) {
      if (lastRead == null || entry.readAt.isAfter(lastRead)) {
        lastRead = entry.readAt;
      }
    }

    final empty =
        entries.isEmpty && readChapters == 0 && downloads.isEmpty;
    if (empty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Statistiques')),
        body: const EmptyView(
          message: 'Aucune donnée pour le moment.\n'
              'Ajoutez des mangas à la bibliothèque et lisez des chapitres.',
          icon: Icons.insights_outlined,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Statistiques')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatSection(
            title: 'Bibliothèque',
            rows: [
              _StatRow('Mangas suivis', '${entries.length}'),
              _StatRow('Chapitres suivis', '$followedChapters'),
              _StatRow('En cours', '$ongoing'),
              _StatRow('Terminés', '$completed'),
              if (otherStatus > 0) _StatRow('Autres statuts', '$otherStatus'),
              _StatRow('Catégories', '$categoryCount'),
            ],
          ),
          _StatSection(
            title: 'Lecture',
            rows: [
              _StatRow('Chapitres lus', '$readChapters'),
              _StatRow('Marque-pages', '$bookmarks'),
              _StatRow(
                'Dernière lecture',
                lastRead == null ? 'Jamais' : formatRelative(lastRead),
              ),
            ],
          ),
          _StatSection(
            title: 'Téléchargements',
            rows: [
              _StatRow('Chapitres téléchargés', '${downloads.length}'),
              _StatRow('Pages téléchargées', '$downloadedPages'),
              _StatRow('Espace utilisé', formatBytes(downloadedBytes)),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatRow {
  const _StatRow(this.label, this.value);

  final String label;
  final String value;
}

class _StatSection extends StatelessWidget {
  const _StatSection({required this.title, required this.rows});

  final String title;
  final List<_StatRow> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(child: Text(row.label)),
                    Text(
                      row.value,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
