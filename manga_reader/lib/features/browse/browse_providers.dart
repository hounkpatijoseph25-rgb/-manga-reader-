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

  @override
  CatalogState build() => const CatalogState();

  /// Ouvre le catalogue d'une source (repart de zéro si la source ou la langue change).
  void start(String sourceId) {
    final language = ref.read(settingsProvider).contentLanguage;
    final same = state.sourceId == sourceId && language == _language;
    if (same && (state.items.isNotEmpty || state.loading)) return;
    _language = language;
    state = CatalogState(sourceId: sourceId);
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
      if (token != _token)
        return; // une recherche plus récente a pris le relais
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
