import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../shared/widgets/manga_card.dart';
import '../../shared/widgets/state_views.dart';
import '../details/details_screen.dart';
import 'browse_providers.dart';

/// Recherche un titre sur toutes les sources visibles en parallèle.
class GlobalSearchScreen extends ConsumerStatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  ConsumerState<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends ConsumerState<GlobalSearchScreen> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit([String? value]) {
    final text = (value ?? _ctrl.text).trim();
    ref.read(globalSearchProvider.notifier).search(text);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(globalSearchProvider);
    final inLibrary = ref.watch(libraryKeysProvider);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Rechercher sur toutes les sources…',
            border: InputBorder.none,
          ),
          onSubmitted: _submit,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Rechercher',
            onPressed: _submit,
          ),
          if (state.query.isNotEmpty || _ctrl.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Effacer',
              onPressed: () {
                _ctrl.clear();
                ref.read(globalSearchProvider.notifier).clear();
              },
            ),
        ],
      ),
      body: _buildBody(context, state, inLibrary),
    );
  }

  Widget _buildBody(
    BuildContext context,
    GlobalSearchState state,
    Set<String> inLibrary,
  ) {
    if (state.query.isEmpty) {
      return const EmptyView(
        icon: Icons.travel_explore,
        message:
            'Tape un titre pour chercher dans toutes les sources activées.',
      );
    }
    if (state.loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Recherche en cours…'),
          ],
        ),
      );
    }

    if (state.results.isEmpty) {
      final err = state.errors.isNotEmpty
          ? '\nSources indisponibles : ${state.errors.join(', ')}'
          : '';
      return EmptyView(message: 'Aucun résultat pour « ${state.query} ».$err');
    }

    final slivers = <Widget>[];
    if (state.errors.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Certaines sources ont échoué : ${state.errors.join(', ')}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
          ),
        ),
      );
    }
    slivers.add(
      SliverPadding(
        padding: const EdgeInsets.all(10),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 130,
            childAspectRatio: 0.58,
          ),
          delegate: SliverChildBuilderDelegate((context, i) {
            final hit = state.results[i];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: MangaCard(
                    manga: hit.manga,
                    showStatus: false,
                    inLibrary: inLibrary.contains(hit.manga.key),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => MangaDetailsScreen(manga: hit.manga),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    hit.sourceName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ),
              ],
            );
          }, childCount: state.results.length),
        ),
      ),
    );

    return CustomScrollView(slivers: slivers);
  }
}
