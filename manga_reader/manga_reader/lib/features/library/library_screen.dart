import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/models/category.dart';
import '../../data/models/library_entry.dart';
import '../../data/models/manga_progress.dart';
import '../../shared/widgets/cover_image.dart';
import '../../shared/widgets/manga_card.dart';
import '../../shared/widgets/state_views.dart';
import '../details/details_screen.dart';

/// Bibliothèque : mangas suivis, par catégories, avec badges de chapitres non lus.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _searchCtrl = TextEditingController();
  bool _searching = false;
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  int _unread(LibraryEntry entry, Map<String, MangaProgress> progress) {
    final read = progress[entry.manga.key]?.readChapterIds.length ?? 0;
    final unread = entry.chapterCount - read;
    return unread < 0 ? 0 : unread;
  }

  void _open(LibraryEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MangaDetailsScreen(manga: entry.manga),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(libraryEntriesProvider);
    final categories =
        ref.watch(categoriesProvider).value ?? const <Category>[];
    final progress =
        ref.watch(allProgressProvider).value ?? const <String, MangaProgress>{};
    final grid = ref.watch(settingsProvider.select((s) => s.libraryGrid));
    final entries = entriesAsync.value ?? const <LibraryEntry>[];
    final tabCount = categories.length + 1;

    return DefaultTabController(
      // Nouvelle clé = le contrôleur d'onglets est recréé quand le nombre de catégories change.
      key: ValueKey(tabCount),
      length: tabCount,
      child: Scaffold(
        appBar: AppBar(
          title: _searching
              ? TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Rechercher dans la bibliothèque',
                    border: InputBorder.none,
                  ),
                  onChanged: (v) =>
                      setState(() => _query = v.trim().toLowerCase()),
                )
              : const Text('Bibliothèque'),
          actions: [
            IconButton(
              icon: Icon(_searching ? Icons.close : Icons.search),
              tooltip: 'Rechercher',
              onPressed: () => setState(() {
                _searching = !_searching;
                if (!_searching) {
                  _searchCtrl.clear();
                  _query = '';
                }
              }),
            ),
            IconButton(
              icon: Icon(grid ? Icons.view_list : Icons.grid_view),
              tooltip: grid ? 'Afficher en liste' : 'Afficher en grille',
              onPressed: () =>
                  ref.read(settingsProvider.notifier).setLibraryGrid(!grid),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'refresh') _refresh();
                if (value == 'categories') _manageCategories();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'refresh',
                  child: Text('Actualiser la bibliothèque'),
                ),
                PopupMenuItem(
                  value: 'categories',
                  child: Text('Gérer les catégories'),
                ),
              ],
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              const Tab(text: 'Tous'),
              for (final c in categories) Tab(text: c.name),
            ],
          ),
        ),
        body: entriesAsync.isLoading && entries.isEmpty
            ? const LoadingView()
            : TabBarView(
                children: [
                  for (var i = 0; i < tabCount; i++)
                    _tab(i, categories, entries, progress, grid),
                ],
              ),
      ),
    );
  }

  Widget _tab(
    int index,
    List<Category> categories,
    List<LibraryEntry> entries,
    Map<String, MangaProgress> progress,
    bool grid,
  ) {
    var items = entries;
    if (index > 0) {
      final categoryId = categories[index - 1].id;
      items = items.where((e) => e.categoryIds.contains(categoryId)).toList();
    }
    if (_query.isNotEmpty) {
      items = items
          .where((e) => e.manga.title.toLowerCase().contains(_query))
          .toList();
    }

    Widget body;
    if (items.isEmpty) {
      // Un ListView permet quand même le "tirer pour actualiser".
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: 320,
            child: EmptyView(
              icon: Icons.collections_bookmark_outlined,
              message: entries.isEmpty
                  ? 'Ta bibliothèque est vide.\nVa dans « Explorer » pour ajouter des mangas.'
                  : 'Aucun manga ici.',
            ),
          ),
        ],
      );
    } else {
      body = grid ? _grid(items, progress) : _list(items, progress);
    }
    return RefreshIndicator(onRefresh: _refresh, child: body);
  }

  Widget _grid(List<LibraryEntry> items, Map<String, MangaProgress> progress) {
    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 130,
        childAspectRatio: 0.64,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final entry = items[i];
        return MangaCard(
          manga: entry.manga,
          unread: _unread(entry, progress),
          onTap: () => _open(entry),
          onLongPress: () => _showMenu(entry),
        );
      },
    );
  }

  Widget _list(List<LibraryEntry> items, Map<String, MangaProgress> progress) {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final entry = items[i];
        final unread = _unread(entry, progress);
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
          subtitle: Text(entry.manga.author ?? entry.manga.status.label),
          trailing: unread > 0 ? Badge(label: Text('$unread')) : null,
          onTap: () => _open(entry),
          onLongPress: () => _showMenu(entry),
        );
      },
    );
  }

  // ---------------------------------------------------------------- actions

  void _showMenu(LibraryEntry entry) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                entry.manga.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.label_outline),
              title: const Text('Changer de catégorie'),
              onTap: () {
                Navigator.pop(ctx);
                _chooseCategories(entry);
              },
            ),
            ListTile(
              leading: const Icon(Icons.done_all),
              title: const Text('Marquer comme lu'),
              onTap: () {
                Navigator.pop(ctx);
                _markAll(entry, true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.remove_done),
              title: const Text('Marquer comme non lu'),
              onTap: () {
                Navigator.pop(ctx);
                _markAll(entry, false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Retirer de la bibliothèque'),
              onTap: () {
                Navigator.pop(ctx);
                _remove(entry);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _markAll(LibraryEntry entry, bool read) async {
    final ids = ref.read(libraryRepositoryProvider).chapterIds(entry.manga.key);
    await ref
        .read(progressRepositoryProvider)
        .setRead(entry.manga.key, ids, read);
  }

  Future<void> _remove(LibraryEntry entry) async {
    await ref.read(libraryRepositoryProvider).remove(entry.manga.key);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('« ${entry.manga.title} » retiré de la bibliothèque'),
      ),
    );
  }

  Future<void> _chooseCategories(LibraryEntry entry) async {
    final categories = ref.read(categoriesProvider).value ?? const <Category>[];
    if (categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Crée d'abord une catégorie (menu ⋮).")),
      );
      return;
    }
    final selected = {...entry.categoryIds};
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Catégories'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final c in categories)
                  CheckboxListTile(
                    value: selected.contains(c.id),
                    title: Text(c.name),
                    onChanged: (v) => setLocal(() {
                      if (v == true) {
                        selected.add(c.id);
                      } else {
                        selected.remove(c.id);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, selected),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      await ref
          .read(libraryRepositoryProvider)
          .setCategories(entry.manga.key, result.toList());
    }
  }

  void _manageCategories() {
    showDialog<void>(
      context: context,
      builder: (_) => const _CategoriesDialog(),
    );
  }

  /// Recharge la liste des chapitres de chaque manga pour mettre à jour les badges.
  Future<void> _refresh() async {
    final entries =
        ref.read(libraryEntriesProvider).value ?? const <LibraryEntry>[];
    final repo = ref.read(libraryRepositoryProvider);
    for (final entry in entries) {
      final source = ref.read(sourceByIdProvider(entry.manga.sourceId));
      if (source == null) continue;
      try {
        final chapters = await source.fetchChapters(entry.manga);
        await repo.saveChapterIds(entry.manga.key, [
          for (final c in chapters) c.id,
        ]);
      } catch (_) {
        // erreur réseau : on passe au manga suivant
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Bibliothèque mise à jour')));
  }
}

/// Boîte de dialogue pour ajouter / supprimer des catégories.
class _CategoriesDialog extends ConsumerStatefulWidget {
  const _CategoriesDialog();

  @override
  ConsumerState<_CategoriesDialog> createState() => _CategoriesDialogState();
}

class _CategoriesDialogState extends ConsumerState<_CategoriesDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final name = _ctrl.text.trim();
    if (name.isEmpty) return;
    await ref.read(categoryRepositoryProvider).add(name);
    _ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final categories =
        ref.watch(categoriesProvider).value ?? const <Category>[];
    return AlertDialog(
      title: const Text('Catégories'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final c in categories)
                ListTile(
                  dense: true,
                  title: Text(c.name),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () =>
                        ref.read(categoryRepositoryProvider).delete(c.id),
                  ),
                ),
              TextField(
                controller: _ctrl,
                decoration: InputDecoration(
                  hintText: 'Nouvelle catégorie',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: _add,
                  ),
                ),
                onSubmitted: (_) => _add(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}
