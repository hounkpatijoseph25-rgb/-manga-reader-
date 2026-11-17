import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/download_folder.dart';
import '../../core/providers.dart';
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
///
/// Sélection multiple (comme Mihon) : appui long sur un chapitre pour entrer en
/// mode sélection, appui simple pour cocher/décocher. En haut : nombre de
/// chapitres sélectionnés, « Inverser la sélection » et « Tout sélectionner ».
/// En bas : Favori, Marquer comme lu, Marquer comme lus tous en dessous,
/// Supprimer les téléchargés.
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

  /// Identifiants des chapitres cochés. Non vide = mode sélection actif.
  final Set<String> _selected = <String>{};

  bool get _selecting => _selected.isNotEmpty;

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
    final loaded = data?.chapters ?? const <Chapter>[];

    // Pas d'écran de chargement si des chapitres sont déjà en cache : on les
    // affiche tout de suite pendant que la mise à jour réseau se fait en fond.
    final chapters = (loaded.isEmpty && detailsAsync.isLoading)
        ? ref.read(chapterCacheRepositoryProvider).load(manga.key)
        : loaded;
    final offline = data?.offline ?? false;
    final inLibrary = ref.watch(libraryKeysProvider).contains(manga.key);
    final progress =
        ref.watch(mangaProgressProvider(manga.key)).value ??
        const MangaProgress();
    // On ne s'abonne qu'aux chapitres TERMINÉS : la progression des
    // téléchargements en cours ne doit pas reconstruire cette page.
    final doneKeys = ref.watch(downloadsProvider.select((s) => s.done));
    final shown = _newestFirst ? chapters.reversed.toList() : chapters;

    // Bouton "Lire" : premier chapitre non lu.
    final allRead =
        chapters.isNotEmpty && chapters.every((c) => progress.isRead(c.id));
    final firstUnread = chapters.indexWhere((c) => !progress.isRead(c.id));
    var startIndex = (allRead || firstUnread < 0) ? 0 : firstUnread;
    if (offline) {
      // Hors connexion, on ne peut ouvrir que ce qui est déjà téléchargé.
      final playable = chapters.asMap().entries.where(
        (e) => doneKeys.contains(DownloadsNotifier.keyOf(manga, e.value)),
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
            expandedHeight: _selecting ? kToolbarHeight : 340,
            leading: _selecting
                ? IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Quitter la sélection',
                    onPressed: _exitSelection,
                  )
                : null,
            title: _selecting
                ? Text(
                    '${_selected.length} sélectionné'
                    '${_selected.length > 1 ? 's' : ''}',
                  )
                : AnimatedOpacity(
                    opacity: _collapsed ? 1 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Text(
                      manga.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
            actions: _selecting
                ? [
                    IconButton(
                      icon: const Icon(Icons.swap_horiz),
                      tooltip: 'Inverser la sélection',
                      onPressed: () => _invertSelection(chapters),
                    ),
                    IconButton(
                      icon: const Icon(Icons.select_all),
                      tooltip: 'Tout sélectionner',
                      onPressed: () => _selectAll(chapters),
                    ),
                  ]
                : [
                    if (manga.sourceId == 'local')
                      IconButton(
                        icon: const Icon(Icons.image_outlined),
                        tooltip: 'Image de présentation',
                        onPressed: () =>
                            showLocalCoverSheet(context, ref, manga),
                      ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Actualiser',
                      onPressed: () =>
                          ref.invalidate(mangaDetailsProvider(widget.manga)),
                    ),
                  ],
            flexibleSpace: _selecting
                ? null
                : FlexibleSpaceBar(
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
                (context, i) {
                  final chapter = shown[i];
                  final chapterKey = DownloadsNotifier.keyOf(manga, chapter);
                  // Le `Consumer` n'abonne que cette ligne au suivi de son
                  // propre téléchargement : un téléchargement en cours ne
                  // reconstruit plus toute la fiche.
                  return Consumer(
                    builder: (context, ref, _) => _tile(
                      manga,
                      chapter,
                      chapters,
                      progress,
                      downloaded: ref.watch(
                        downloadsProvider.select(
                          (s) => s.done.contains(chapterKey),
                        ),
                      ),
                      offline: offline,
                      selecting: _selecting,
                    ),
                  );
                },
                childCount: shown.length,
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
      bottomNavigationBar: _selecting
          ? _selectionBar(manga, chapters, shown)
          : null,
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
              if (manga.sourceId != 'downloads')
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

  /// Barre du bas affichée en mode sélection : 4 actions groupées.
  Widget _selectionBar(Manga manga, List<Chapter> chapters, List<Chapter> shown) {
    final progress =
        ref.watch(mangaProgressProvider(manga.key)).value ??
        const MangaProgress();
    final doneKeys = ref.watch(downloadsProvider.select((s) => s.done));
    final ids = _selected;

    final allRead = ids.every(progress.isRead);
    final allBookmarked = ids.every(progress.isBookmarked);
    final selectedChapters = [
      for (final c in chapters)
        if (ids.contains(c.id)) c,
    ];
    final anyDownloaded = selectedChapters.any(
      (c) => doneKeys.contains(DownloadsNotifier.keyOf(manga, c)),
    );

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              _SelectAction(
                icon: allBookmarked ? Icons.bookmark : Icons.bookmark_border,
                label: 'Favori',
                onTap: () => _toggleBookmark(manga, ids),
              ),
              _SelectAction(
                icon: allRead ? Icons.remove_done : Icons.done_all,
                label: allRead ? 'Non lu' : 'Marquer lu',
                onTap: () => _setRead(manga, ids, !allRead),
              ),
              _SelectAction(
                icon: Icons.done_all,
                label: 'Lus en dessous',
                onTap: () => _markReadBelow(manga, shown, ids),
              ),
              _SelectAction(
                icon: Icons.delete_outline,
                label: 'Suppr. téléch.',
                onTap: anyDownloaded
                    ? () => _deleteDownloads(manga, chapters, ids)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(
    Manga manga,
    Chapter chapter,
    List<Chapter> ascending,
    MangaProgress progress, {
    required bool downloaded,
    required bool offline,
    required bool selecting,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final read = progress.isRead(chapter.id);
    final page = progress.pageOf(chapter.id);
    final bookmarked = progress.isBookmarked(chapter.id);
    final selected = _selected.contains(chapter.id);
    final scanlator = chapter.scanlator;
    // Chaque info est (texte, mis en avant). La page en cours est mise en
    // avant : sa couleur diffère du nom du chapitre pour se repérer d'un coup
    // d'œil en revenant sur la fiche après avoir quitté un chapitre.
    final meta = <(String, bool)>[
      if (chapter.publishedAt != null) (formatDate(chapter.publishedAt), false),
      if (scanlator != null && scanlator.isNotEmpty) (scanlator, false),
      if (!read && page > 0) ('page ${page + 1}', true),
      if (downloaded) ('hors ligne', false),
    ];

    return ListTile(
      selected: selected,
      selectedTileColor: scheme.primary.withValues(alpha: 0.12),
      leading: selecting
          ? Checkbox(
              value: selected,
              visualDensity: VisualDensity.compact,
              onChanged: (_) => _toggleSelect(chapter.id),
            )
          : SizedBox(
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
        style: read && !selecting ? TextStyle(color: scheme.outline) : null,
      ),
      subtitle: meta.isEmpty
          ? null
          : Text.rich(
              TextSpan(
                children: [
                  for (var i = 0; i < meta.length; i++) ...[
                    if (i > 0) const TextSpan(text: ' · '),
                    TextSpan(
                      text: meta[i].$1,
                      style: meta[i].$2
                          ? TextStyle(
                              color: scheme.primary,
                              fontWeight: FontWeight.w600,
                            )
                          : null,
                    ),
                  ],
                ],
              ),
            ),
      trailing: selecting
          ? (bookmarked
                ? Icon(Icons.bookmark, color: scheme.primary)
                : const SizedBox.shrink())
          : manga.sourceId == 'downloads'
          ? Icon(Icons.download_done, color: scheme.primary)
          : _downloadButton(
              manga,
              chapter,
              offline: offline,
            ),
      onTap: () {
        if (selecting) {
          _toggleSelect(chapter.id);
          return;
        }
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
      // Appui long = entrer en mode sélection (ou marquer lu si déjà actif).
      onLongPress: () {
        if (!selecting) {
          _startSelection(chapter.id);
        } else {
          _toggleSelect(chapter.id);
        }
      },
    );
  }

  Widget _downloadButton(
    Manga manga,
    Chapter chapter, {
    required bool offline,
  }) {
    final key = DownloadsNotifier.keyOf(manga, chapter);
    final notifier = ref.read(downloadsProvider.notifier);
    // Abonnement isolé à CE chapitre : la progression d'un téléchargement ne
    // reconstruit que ce bouton, pas toute la fiche.
    return Consumer(
      builder: (context, ref, _) {
        final active = ref.watch(downloadsProvider.select((s) => s.active[key]));
        final queued = ref.watch(
          downloadsProvider.select((s) => s.queued.containsKey(key)),
        );
        final done = ref.watch(
          downloadsProvider.select((s) => s.done.contains(key)),
        );
        final failed = ref.watch(
          downloadsProvider.select((s) => s.failed.contains(key)),
        );

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
        if (queued) {
          return const Tooltip(
            message: 'En attente',
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(Icons.schedule, size: 20),
            ),
          );
        }
        if (done) {
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
            failed ? Icons.error_outline : Icons.download_outlined,
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
      },
    );
  }

  // --------------------------------------------------------- sélection multiple

  void _startSelection(String id) => setState(() => _selected.add(id));

  void _toggleSelect(String id) => setState(() {
    if (!_selected.add(id)) _selected.remove(id);
  });

  void _exitSelection() => setState(_selected.clear);

  void _selectAll(List<Chapter> chapters) => setState(() {
    _selected
      ..clear()
      ..addAll(chapters.map((c) => c.id));
  });

  void _invertSelection(List<Chapter> chapters) => setState(() {
    final all = chapters.map((c) => c.id).toSet();
    _selected
      ..clear()
      ..addAll(all.difference(_selected));
  });

  Future<void> _toggleBookmark(Manga manga, Set<String> ids) async {
    final progress =
        ref.read(mangaProgressProvider(manga.key)).value ??
        const MangaProgress();
    final allBookmarked = ids.every(progress.isBookmarked);
    await ref
        .read(progressRepositoryProvider)
        .setBookmarked(manga.key, ids, !allBookmarked);
  }

  Future<void> _setRead(Manga manga, Set<String> ids, bool read) async {
    await ref.read(progressRepositoryProvider).setRead(manga.key, ids, read);
  }

  /// Marque comme lus le chapitre sélectionné le plus bas **et tout ce qui est
  /// en dessous** dans la liste affichée (donc les chapitres plus anciens).
  Future<void> _markReadBelow(
    Manga manga,
    List<Chapter> shown,
    Set<String> ids,
  ) async {
    var anchor = -1;
    for (var i = 0; i < shown.length; i++) {
      if (ids.contains(shown[i].id)) anchor = i; // le plus bas sélectionné
    }
    if (anchor < 0) return;
    final targets = shown.sublist(anchor).map((c) => c.id).toList();
    await ref.read(progressRepositoryProvider).setRead(manga.key, targets, true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${targets.length} chapitre(s) marqué(s) comme lus')),
    );
  }

  Future<void> _deleteDownloads(
    Manga manga,
    List<Chapter> chapters,
    Set<String> ids,
  ) async {
    final downloads = ref.read(downloadsProvider);
    final notifier = ref.read(downloadsProvider.notifier);
    final targets = [
      for (final c in chapters)
        if (ids.contains(c.id) &&
            downloads.done.contains(DownloadsNotifier.keyOf(manga, c)))
          c,
    ];
    if (targets.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer les téléchargements'),
        content: Text(
          'Supprimer ${targets.length} chapitre(s) téléchargé(s) ?\n'
          'Les fichiers seront retirés du téléphone.',
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

    for (final c in targets) {
      await notifier.remove(manga, c);
    }
    if (!mounted) return;
    setState(_selected.clear);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${targets.length} téléchargement(s) supprimé(s)')),
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

/// Une des quatre actions de la barre de sélection.
class _SelectAction extends StatelessWidget {
  const _SelectAction({
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final color = enabled
        ? Theme.of(context).colorScheme.onSurface
        : Theme.of(context).disabledColor;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: color),
            ),
          ],
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
