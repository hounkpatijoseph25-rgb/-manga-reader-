import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/utils/errors.dart';
import '../../data/models/manga.dart';
import '../../data/sources/manga_source.dart';
import '../../shared/widgets/manga_card.dart';
import '../../shared/widgets/state_views.dart';
import '../details/details_screen.dart';
import 'browse_providers.dart';

/// Catalogue d'une source : grille paginée, recherche, filtres et tri.
class CatalogueScreen extends ConsumerStatefulWidget {
  const CatalogueScreen({super.key, required this.source});

  final MangaSource source;

  @override
  ConsumerState<CatalogueScreen> createState() => _CatalogueScreenState();
}

class _CatalogueScreenState extends ConsumerState<CatalogueScreen> {
  final _scroll = ScrollController();
  final _searchCtrl = TextEditingController();
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // On attend la fin de la construction avant de modifier un provider.
    Future.microtask(() {
      if (mounted) ref.read(catalogProvider.notifier).start(widget.source.id);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 600) {
      ref.read(catalogProvider.notifier).loadMore();
    }
  }

  void _toggleSearch() {
    final hadQuery = ref.read(catalogProvider).query.text.isNotEmpty;
    setState(() => _searching = !_searching);
    if (!_searching) {
      _searchCtrl.clear();
      if (hadQuery) ref.read(catalogProvider.notifier).setQuery('');
    }
  }

  void _openFilters() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FilterSheet(sourceId: widget.source.id),
    );
  }

  void _open(Manga manga) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => MangaDetailsScreen(manga: manga)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(catalogProvider);
    final inLibrary = ref.watch(libraryKeysProvider);
    final ready = state.sourceId == widget.source.id;

    final slivers = <Widget>[
      SliverAppBar(
        floating: true,
        snap: true,
        title: _searching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Rechercher un titre…',
                  border: InputBorder.none,
                ),
                onSubmitted: (v) =>
                    ref.read(catalogProvider.notifier).setQuery(v),
              )
            : Text(widget.source.name),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            tooltip: 'Rechercher',
            onPressed: _toggleSearch,
          ),
          IconButton(
            icon: Badge(
              isLabelVisible: ready && state.query.hasFilters,
              smallSize: 8,
              child: const Icon(Icons.filter_list),
            ),
            tooltip: 'Filtres et tri',
            onPressed: _openFilters,
          ),
        ],
      ),
    ];

    if (!ready || (state.items.isEmpty && state.loading)) {
      slivers.add(
        const SliverFillRemaining(hasScrollBody: false, child: LoadingView()),
      );
    } else if (state.items.isEmpty && state.error != null) {
      slivers.add(
        SliverFillRemaining(
          hasScrollBody: false,
          child: ErrorView(
            message: describeError(state.error!),
            onRetry: () => ref.read(catalogProvider.notifier).retry(),
          ),
        ),
      );
    } else if (state.items.isEmpty) {
      slivers.add(
        const SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyView(message: 'Aucun résultat'),
        ),
      );
    } else {
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 130,
              childAspectRatio: 0.64,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            delegate: SliverChildBuilderDelegate((context, i) {
              final manga = state.items[i];
              return MangaCard(
                manga: manga,
                showStatus: true,
                inLibrary: inLibrary.contains(manga.key),
                onTap: () => _open(manga),
              );
            }, childCount: state.items.length),
          ),
        ),
      );
      slivers.add(SliverToBoxAdapter(child: _footer(state)));
    }

    return Scaffold(
      body: CustomScrollView(controller: _scroll, slivers: slivers),
    );
  }

  Widget _footer(CatalogState state) {
    if (state.loading) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (state.error != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Center(
          child: TextButton.icon(
            onPressed: () => ref.read(catalogProvider.notifier).retry(),
            icon: const Icon(Icons.refresh),
            label: Text('${describeError(state.error!)} Réessayer'),
          ),
        ),
      );
    }
    return const SizedBox(height: 24);
  }
}

/// Panneau de filtres : tri + genres.
class _FilterSheet extends ConsumerWidget {
  const _FilterSheet({required this.sourceId});

  final String sourceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(catalogProvider.select((s) => s.query));
    final genres = ref.watch(genresProvider(sourceId));
    final notifier = ref.read(catalogProvider.notifier);
    final titleStyle = Theme.of(context).textTheme.titleMedium;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('Trier par', style: titleStyle),
                const Spacer(),
                TextButton(
                  onPressed: notifier.clearFilters,
                  child: const Text('Réinitialiser'),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final sort in CatalogSort.values)
                  ChoiceChip(
                    label: Text(sort.label),
                    selected: query.sort == sort,
                    onSelected: (_) => notifier.setSort(sort),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Genres', style: titleStyle),
            const SizedBox(height: 8),
            genres.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text(describeError(e)),
              data: (list) => list.isEmpty
                  ? const Text('Aucun genre disponible pour cette source.')
                  : Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final genre in list)
                          FilterChip(
                            label: Text(genre.name),
                            selected: query.genreIds.contains(genre.id),
                            onSelected: (_) => notifier.toggleGenre(genre.id),
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
