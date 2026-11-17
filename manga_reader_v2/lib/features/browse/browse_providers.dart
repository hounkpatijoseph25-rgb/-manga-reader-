import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/models/manga.dart';
import '../../data/sources/manga_source.dart';

/// État du catalogue d'une source : liste paginée + recherche + filtres.
class CatalogState {
  const CatalogState({
    this.sourceId = '',
    this.items = const [],
    this.page = 0,
    this.hasNext = true,
    this.loading = false,
    this.error,
    this.query = const CatalogQuery(),
  });

  final String sourceId;
  final List<Manga> items;
  final int page;
  final bool hasNext;
  final bool loading;
  final Object? error;
  final CatalogQuery query;

  CatalogState copyWith({
    String? sourceId,
    List<Manga>? items,
    int? page,
    bool? hasNext,
    bool? loading,
    Object? error,
    bool clearError = false,
    CatalogQuery? query,
  }) {
    return CatalogState(
      sourceId: sourceId ?? this.sourceId,
      items: items ?? this.items,
      page: page ?? this.page,
      hasNext: hasNext ?? this.hasNext,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      query: query ?? this.query,
    );
  }
}

class CatalogNotifier extends Notifier<CatalogState> {
  int _token = 0;
  String _language = '';
  String _localRoot = '';

  @override
  CatalogState build() => const CatalogState();

  /// Ouvre le catalogue d'une source. Il repart de zéro si la source, la langue
  /// ou le dossier de la bibliothèque locale ont changé depuis le dernier appel.
  void start(String sourceId) {
    final language = ref.read(settingsProvider).contentLanguage;
    final localRoot = ref.read(settingsProvider).localRoot;
    final same = state.sourceId == sourceId &&
        language == _language &&
        localRoot == _localRoot;
    if (same && (state.items.isNotEmpty || state.loading)) return;
    _language = language;
    _localRoot = localRoot;
    state = CatalogState(sourceId: sourceId);
    _loadFirstPage();
  }

  /// Recharge immédiatement le catalogue affiché (changement de dossier local).
  void refresh() {
    if (state.sourceId.isEmpty) return;
    _loadFirstPage();
  }

  void setQuery(String text) => _changeQuery(state.query.copyWith(text: text));

  void setSort(CatalogSort sort) =>
      _changeQuery(state.query.copyWith(sort: sort));

  void toggleGenre(String genreId) {
    final ids = {...state.query.genreIds};
    if (!ids.add(genreId)) ids.remove(genreId);
    _changeQuery(state.query.copyWith(genreIds: ids));
  }

  void clearFilters() => _changeQuery(CatalogQuery(text: state.query.text));

  void retry() {
    state = state.copyWith(clearError: true);
    if (state.items.isEmpty) {
      _loadFirstPage();
    } else {
      loadMore();
    }
  }

  void _changeQuery(CatalogQuery query) {
    state = state.copyWith(query: query);
    _loadFirstPage();
  }

  Future<void> _loadFirstPage() async {
    final token = ++_token;
    state = state.copyWith(
      items: const [],
      page: 0,
      hasNext: true,
      loading: true,
      clearError: true,
    );
    await _fetch(token, 1);
  }

  /// Charge la page suivante (appelé quand on arrive en bas de la grille).
  Future<void> loadMore() async {
    if (state.loading ||
        !state.hasNext ||
        state.sourceId.isEmpty ||
        state.error != null) {
      return;
    }
    state = state.copyWith(loading: true);
    await _fetch(_token, state.page + 1);
  }

  Future<void> _fetch(int token, int page) async {
    final source = ref.read(sourceByIdProvider(state.sourceId));
    if (source == null) {
      state = state.copyWith(loading: false, error: 'Source introuvable.');
      return;
    }
    try {
      final result = await source.fetchCatalog(page: page, query: state.query);
      if (token != _token) {
        return; // une recherche plus récente a pris le relais
      }
      final known = {for (final m in state.items) m.id};
      state = state.copyWith(
        items: [
          ...state.items,
          ...result.mangas.where((m) => !known.contains(m.id)),
        ],
        page: page,
        hasNext: result.hasNextPage,
        loading: false,
      );
    } catch (e) {
      if (token != _token) return;
      state = state.copyWith(loading: false, error: e);
    }
  }
}

final catalogProvider = NotifierProvider<CatalogNotifier, CatalogState>(
  CatalogNotifier.new,
);

/// Liste des genres d'une source (pour le filtre).
final genresProvider = FutureProvider.family<List<Genre>, String>((
  ref,
  sourceId,
) async {
  final source = ref.watch(sourceByIdProvider(sourceId));
  if (source == null) return const <Genre>[];
  return source.fetchGenres();
});

/// Résultat d'une recherche globale (manga + nom de source pour affichage).
class GlobalSearchHit {
  const GlobalSearchHit({required this.manga, required this.sourceName});

  final Manga manga;
  final String sourceName;
}

/// État de la recherche globale multi-sources.
class GlobalSearchState {
  const GlobalSearchState({
    this.query = '',
    this.loading = false,
    this.results = const [],
    this.errors = const [],
  });

  final String query;
  final bool loading;
  final List<GlobalSearchHit> results;
  final List<String> errors;

  GlobalSearchState copyWith({
    String? query,
    bool? loading,
    List<GlobalSearchHit>? results,
    List<String>? errors,
  }) {
    return GlobalSearchState(
      query: query ?? this.query,
      loading: loading ?? this.loading,
      results: results ?? this.results,
      errors: errors ?? this.errors,
    );
  }
}

class GlobalSearchNotifier extends Notifier<GlobalSearchState> {
  int _token = 0;

  @override
  GlobalSearchState build() => const GlobalSearchState();

  Future<void> search(String text) async {
    final query = text.trim();
    if (query.isEmpty) {
      state = const GlobalSearchState();
      return;
    }
    final token = ++_token;
    state = GlobalSearchState(query: query, loading: true);

    final sources = ref
        .read(sourcesProvider)
        .where((s) => s.id != 'local')
        .toList();

    final results = <GlobalSearchHit>[];
    final errors = <String>[];
    final futures = sources.map((source) async {
      try {
        final page = await source.fetchCatalog(
          page: 1,
          query: CatalogQuery(text: query),
        );
        return (source, page.mangas, null);
      } catch (e) {
        return (source, const <Manga>[], e);
      }
    });

    final settled = await Future.wait(futures);
    if (token != _token) return;

    final seen = <String>{};
    for (final entry in settled) {
      final source = entry.$1;
      final mangas = entry.$2;
      final err = entry.$3;
      if (err != null) {
        errors.add(source.name);
        continue;
      }
      for (final m in mangas) {
        if (seen.add(m.key)) {
          results.add(GlobalSearchHit(manga: m, sourceName: source.name));
        }
      }
    }

    state = GlobalSearchState(
      query: query,
      loading: false,
      results: results,
      errors: errors,
    );
  }

  void clear() {
    _token++;
    state = const GlobalSearchState();
  }
}

final globalSearchProvider =
    NotifierProvider<GlobalSearchNotifier, GlobalSearchState>(
  GlobalSearchNotifier.new,
);
