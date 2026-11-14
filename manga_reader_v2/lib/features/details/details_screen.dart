import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/download_folder.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/format.dart';
import '../../data/models/chapter.dart';
import '../../data/models/manga.dart';
import '../../data/models/manga_progress.dart';
import '../../shared/widgets/cover_image.dart';
import '../../shared/widgets/expandable_text.dart';
import '../../shared/widgets/state_views.dart';
import '../browse/local_library.dart';
import '../downloads/downloads_provider.dart';
import '../reader/reader_screen.dart';
import 'details_providers.dart';

/// Page d'un manga : en-tête, boutons d'action, synopsis et liste des chapitres.
class MangaDetailsScreen extends ConsumerStatefulWidget {
  const MangaDetailsScreen({super.key, required this.manga});

  final Manga manga;

  @override
  ConsumerState<MangaDetailsScreen> createState() => _MangaDetailsScreenState();
}

class _MangaDetailsScreenState extends ConsumerState<MangaDetailsScreen> {
  final _scroll = ScrollController();
  bool _collapsed = false;
  bool _newestFirst = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final collapsed = _scroll.hasClients && _scroll.offset > 250;
      if (collapsed != _collapsed) setState(() => _collapsed = collapsed);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detailsAsync = ref.watch(mangaDetailsProvider(widget.manga));

    // Dès que les chapitres arrivent, on regarde lesquels sont déjà téléchargés.
    ref.listen<AsyncValue<DetailsData>>(mangaDetailsProvider(widget.manga), (
      previous,
      next,
    ) {
      final data = next.value;
      if (data != null) {
        ref.read(downloadsProvider.notifier).scan(data.manga, data.chapters);
      }
    });

    final data = detailsAsync.value;
    final manga = data?.manga ?? widget.manga;
    final chapters =
        data?.chapters ?? const <Chapter>[]; // du plus ancien au plus récent
    final offline = data?.offline ?? false;
    final inLibrary = ref.watch(libraryKeysProvider).contains(manga.key);
    final progress =
        ref.watch(mangaProgressProvider(manga.key)).value ??
        const MangaProgress();
    final downloads = ref.watch(downloadsProvider);
    final shown = _newestFirst ? chapters.reversed.toList() : chapters;

    // Bouton "Lire" : premier chapitre non lu.
    final allRead =
        chapters.isNotEmpty && chapters.every((c) => progress.isRead(c.id));
    final firstUnread = chapters.indexWhere((c) => !progress.isRead(c.id));
    var startIndex = (allRead || firstUnread < 0) ? 0 : firstUnread;
    if (offline) {
      // Hors connexion, on ne peut ouvrir que ce qui est déjà téléchargé.
      final playable = chapters.asMap().entries.where(
        (e) => downloads.done.contains(
          DownloadsNotifier.keyOf(manga, e.value),
        ),
      );
      if (playable.isEmpty) {
        startIndex = -1;
      } else {
        final unread = playable.where((e) => !progress.isRead(e.value.id));
        startIndex = (unread.isNotEmpty ? unread.first : playable.first).key;
      }
    }
    final String readLabel;
    if (chapters.isEmpty || startIndex < 0) {
      readLabel = offline ? 'Aucun chapitre hors ligne' : 'Lire';
    } else if (allRead) {
      readLabel = 'Relire';
    } else if (progress.isEmpty) {
      readLabel = 'Lire';
    } else {
      readLabel = 'Continuer · ${chapters[startIndex].displayTitle}';
    }

    return Scaffold(
      body: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 340,
            title: AnimatedOpacity(
              opacity: _collapsed ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: Text(
                manga.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            actions: [
              if (manga.sourceId == 'local')
                IconButton(
                  icon: const Icon(Icons.image_outlined),
                  tooltip: 'Image de présentation',
                  onPressed: () => showLocalCoverSheet(context, ref, manga),
                ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Actualiser',
                onPressed: () =>
                    ref.invalidate(mangaDetailsProvider(widget.manga)),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.parallax,
              background: _Header(manga: manga),
            ),
          ),
          SliverToBoxAdapter(
            child: _actions(
              manga: manga,
              chapters: chapters,
              inLibrary: inLibrary,
              canAdd: data != null || inLibrary,
              readLabel: readLabel,
              startIndex: startIndex,
              offline: offline,
            ),
          ),
          if (offline)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Hors connexion · liste des chapitres en cache. '
                        'Seuls les chapitres téléchargés sont lisibles.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (manga.genres.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final genre in manga.genres)
                      Chip(
                        label: Text(genre),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
            ),
          if (manga.description.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: ExpandableText(manga.description),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: [
                  Text(
                    '${chapters.length} chapitre${chapters.length > 1 ? 's' : ''}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.swap_vert),
                    tooltip: "Inverser l'ordre",
                    onPressed: () =>
                        setState(() => _newestFirst = !_newestFirst),
                  ),
                ],
              ),
            ),
          ),
          if (detailsAsync.isLoading && chapters.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (detailsAsync.hasError && chapters.isEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 240,
                child: ErrorView(
                  message: describeError(detailsAsync.error!),
                  onRetry: () =>
                      ref.invalidate(mangaDetailsProvider(widget.manga)),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _tile(
                  manga,
                  shown[i],
                  chapters,
                  progress,
                  downloads,
                  offline: offline,
                ),
                childCount: shown.length,
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- widgets

  Widget _actions({
    required Manga manga,
    required List<Chapter> chapters,
    required bool inLibrary,
    required bool canAdd,
    required String readLabel,
    required int startIndex,
    required bool offline,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: chapters.isEmpty || startIndex < 0
                  ? null
                  : () => _openReader(manga, chapters, startIndex),
              icon: const Icon(Icons.play_arrow),
              label: Text(
                readLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: canAdd
                      ? () => _toggleLibrary(manga, chapters, inLibrary)
                      : null,
                  icon: Icon(
                    inLibrary ? Icons.favorite : Icons.favorite_border,
                  ),
                  label: Text(
                    inLibrary
                        ? 'Dans la bibliothèque'
                        : 'Ajouter à la bibliothèque',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: chapters.isEmpty || offline
                    ? null
                    : () => _downloadMenu(manga, chapters),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Télécharger'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tile(
    Manga manga,
    Chapter chapter,
    List<Chapter> ascending,
    MangaProgress progress,
    DownloadsState downloads, {
    required bool offline,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final read = progress.isRead(chapter.id);
    final page = progress.pageOf(chapter.id);
    final scanlator = chapter.scanlator;
    final downloaded = downloads.done.contains(
      DownloadsNotifier.keyOf(manga, chapter),
    );
    final info = <String>[
      if (chapter.publishedAt != null) formatDate(chapter.publishedAt),
      if (scanlator != null && scanlator.isNotEmpty) scanlator,
      if (!read && page > 0) 'page ${page + 1}',
      if (downloaded) 'hors ligne',
    ];

    return ListTile(
      leading: SizedBox(
        width: 24,
        child: Center(
          child: Icon(
            read ? Icons.done_all : Icons.fiber_manual_record,
            size: read ? 20 : 12,
            color: read ? scheme.outline : scheme.primary,
          ),
        ),
      ),
      title: Text(
        chapter.displayTitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: read ? TextStyle(color: scheme.outline) : null,
      ),
      subtitle: info.isEmpty ? null : Text(info.join(' · ')),
      trailing: _downloadButton(
        manga,
        chapter,
        downloads,
        offline: offline,
      ),
      onTap: () {
        if (offline && !downloaded) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Chapitre non téléchargé : il faut une connexion pour le lire.',
              ),
            ),
          );
          return;
        }
        _openReader(
          manga,
          ascending,
          ascending.indexWhere((c) => c.id == chapter.id),
        );
      },
      // Appui long = marquer comme lu / non lu.
      onLongPress: () => ref.read(progressRepositoryProvider).setRead(
        manga.key,
        [chapter.id],
        !read,
      ),
    );
  }

  Widget _downloadButton(
    Manga manga,
    Chapter chapter,
    DownloadsState downloads, {
    required bool offline,
  }) {
    final key = DownloadsNotifier.keyOf(manga, chapter);
    final notifier = ref.read(downloadsProvider.notifier);
    final active = downloads.active[key];

    if (active != null) {
      return SizedBox(
        width: 40,
        height: 40,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            value: active.progress > 0 ? active.progress : null,
          ),
        ),
      );
    }
    if (downloads.done.contains(key)) {
      return IconButton(
        icon: Icon(
          Icons.download_done,
          color: Theme.of(context).colorScheme.primary,
        ),
        tooltip: 'Téléchargé – appuie pour supprimer',
        onPressed: () => notifier.remove(manga, chapter),
      );
    }
    return IconButton(
      icon: Icon(
        downloads.failed.contains(key)
            ? Icons.error_outline
            : Icons.download_outlined,
      ),
      tooltip: offline
          ? 'Téléchargement impossible hors connexion'
          : 'Télécharger',
      onPressed: offline
          ? null
          : () async {
              final ok = await ensureDownloadsLocation(context, ref);
              if (!ok || !context.mounted) return;
              notifier.enqueue(manga, [chapter]);
            },
    );
  }

  // ----------------------------------------------------------------- actions

  void _openReader(Manga manga, List<Chapter> ascending, int index) {
    if (index < 0) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReaderScreen(
          manga: manga,
          chapters: ascending,
          initialIndex: index,
        ),
      ),
    );
  }

  Future<void> _toggleLibrary(
    Manga manga,
    List<Chapter> chapters,
    bool inLibrary,
  ) async {
    final repo = ref.read(libraryRepositoryProvider);
    if (inLibrary) {
      await repo.remove(manga.key);
    } else {
      await repo.add(manga, chapterIds: [for (final c in chapters) c.id]);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          inLibrary ? 'Retiré de la bibliothèque' : 'Ajouté à la bibliothèque',
        ),
      ),
    );
  }

  void _downloadMenu(Manga manga, List<Chapter> ascending) {
    final progress =
        ref.read(mangaProgressProvider(manga.key)).value ??
        const MangaProgress();
    final unread = ascending.where((c) => !progress.isRead(c.id)).toList();

    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Les 5 prochains chapitres non lus'),
              onTap: () {
                Navigator.pop(ctx);
                _enqueue(manga, unread.take(5).toList());
              },
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Tous les chapitres non lus'),
              onTap: () {
                Navigator.pop(ctx);
                _enqueue(manga, unread);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Tous les chapitres'),
              onTap: () {
                Navigator.pop(ctx);
                _enqueue(manga, ascending);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _enqueue(Manga manga, List<Chapter> chapters) async {
    if (chapters.isEmpty) return;
    final ok = await ensureDownloadsLocation(context, ref);
    if (!ok || !mounted) return;
    ref.read(downloadsProvider.notifier).enqueue(manga, chapters);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${chapters.length} chapitre(s) ajouté(s) aux téléchargements',
        ),
      ),
    );
  }
}

/// En-tête immersif : couverture floutée en fond + couverture, titre, auteur, statut.
class _Header extends ConsumerWidget {
  const _Header({required this.manga});

  final Manga manga;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cover = manga.coverUrl;
    final author = manga.author;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (cover != null)
          ClipRect(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: CachedNetworkImage(
                imageUrl: cover,
                fit: BoxFit.cover,
                httpHeaders: ref.watch(urlHeadersProvider)(cover),
              ),
            ),
          ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black45, Colors.black87],
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, kToolbarHeight, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  width: 120,
                  height: 180,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CoverImage(url: cover),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        manga.title,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (author != null)
                        Text(
                          author,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      Text(
                        manga.status.label,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
