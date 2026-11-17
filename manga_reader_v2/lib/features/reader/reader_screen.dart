import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/providers.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/format.dart';
import '../../data/models/chapter.dart';
import '../../data/models/manga.dart';
import '../../data/models/manga_page.dart';
import '../../data/repositories/history_repository.dart';
import '../../data/repositories/progress_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../shared/widgets/choice_sheet.dart';
import 'zoomable_view.dart';

/// Lecteur de chapitres : mode vertical (webtoon), horizontal (G→D ou D→G) ou double page.
///
/// - Appui au centre : affiche / masque les barres.
/// - Appui sur les bords (modes horizontaux) : page précédente / suivante.
/// - Pincer : zoom (modes horizontaux).
/// - La position (page ou défilement webtoon) est enregistrée en continu.
///
/// Mode webtoon : défilement vertical continu, plein écran, sans rebond ni
/// « remontée » accidentelle. La position est suivie par index de page (via
/// [ScrollablePositionedList]) et non par pixels : la page courante reste donc
/// exacte malgré les hauteurs variables des images, et la reprise à l'ouverture
/// retombe précisément sur la bonne page.
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({
    super.key,
    required this.manga,
    required this.chapters,
    required this.initialIndex,
  });

  final Manga manga;

  /// Tous les chapitres, du plus ancien au plus récent.
  final List<Chapter> chapters;
  final int initialIndex;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen>
    with WidgetsBindingObserver {
  late final ProgressRepository _progressRepo;
  late final HistoryRepository _historyRepo;
  late int _chapterIndex;
  late ReaderMode _mode;

  List<MangaPage>? _pages;
  Object? _error;
  int _page = 0; // page courante (0 = première)
  bool _reachedEnd = false;
  bool _showBars = true;
  bool _zoomed = false;
  int _loadToken = 0;

  /// Page courante diffusée uniquement à la barre du bas.
  ///
  /// En mode webtoon la page change à chaque écran parcouru : un `setState`
  /// reconstruirait tout le lecteur (barres, liste, images) plusieurs fois par
  /// seconde pendant le défilement — c'est la principale cause de saccade.
  final ValueNotifier<int> _pageNotifier = ValueNotifier<int>(0);

  PageController? _pageController;
  List<List<int>> _spreads = const [];

  // --- Mode webtoon ---------------------------------------------------------
  /// Suit la position de défilement par index de page (et non par pixels) : la
  /// page courante reste exacte même quand les hauteurs réelles des images
  /// diffèrent des estimations, et la restauration est précise.
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  /// Page à restaurer au premier affichage du chapitre.
  int _restorePage = 0;
  Timer? _saveDebounce;

  Chapter get _chapter => widget.chapters[_chapterIndex];
  int get _count => _pages?.length ?? 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _progressRepo = ref.read(progressRepositoryProvider);
    _historyRepo = ref.read(historyRepositoryProvider);
    _chapterIndex = widget.initialIndex;
    _mode = ref.read(settingsProvider).readerMode;
    _itemPositionsListener.itemPositions.addListener(_onPositionsChanged);
    _applyScreenPreferences();
    _loadChapter();
  }

  /// Garde l'écran allumé et applique la luminosité choisie pour le lecteur.
  void _applyScreenPreferences() {
    final settings = ref.read(settingsProvider);
    if (settings.keepScreenOn) {
      WakelockPlus.enable().ignore();
    }
    final brightness = settings.readerBrightness;
    if (brightness >= 0) {
      ScreenBrightness().setApplicationScreenBrightness(brightness).ignore();
    }
  }

  /// Rend la luminosité au système (à la fermeture du lecteur).
  void _restoreScreenPreferences() {
    WakelockPlus.disable().ignore();
    ScreenBrightness().resetApplicationScreenBrightness().ignore();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _saveProgress(); // sauvegarde de la position
    WidgetsBinding.instance.removeObserver(this);
    _itemPositionsListener.itemPositions.removeListener(_onPositionsChanged);
    _pageNotifier.dispose();
    _pageController?.dispose();
    _restoreScreenPreferences();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _saveProgress();
  }

  // ---------------------------------------------------------------- chargement

  void _resetForLoad() {
    _pages = null;
    _error = null;
    _page = 0;
    _reachedEnd = false;
    _zoomed = false;
    _restorePage = 0;
    _pageNotifier.value = 0;
  }

  Future<void> _loadChapter() async {
    final token = ++_loadToken;
    try {
      final manga = widget.manga;
      final chapter = _chapter;

      // 1) chapitre téléchargé ? 2) sinon on demande les pages à la source.
      final local = await ref
          .read(downloadServiceProvider)
          .localPages(manga, chapter);
      final List<MangaPage> pages;
      if (local != null) {
        pages = [
          for (var i = 0; i < local.length; i++)
            MangaPage(index: i, imageUrl: '', localPath: local[i]),
        ];
      } else {
        final source = ref.read(sourceByIdProvider(manga.sourceId));
        if (source == null) throw StateError('Source introuvable.');
        pages = await source.fetchPages(chapter);
      }
      if (!mounted || token != _loadToken) return;
      if (pages.isEmpty) {
        throw StateError('Ce chapitre ne contient aucune page.');
      }

      // Reprise : page à restaurer (l'index suffit, tous modes confondus).
      final progress = _progressRepo.get(manga.key);
      final read = progress.isRead(chapter.id);
      _restorePage = read ? 0 : progress.pageOf(chapter.id);

      setState(() {
        _pages = pages;
        _page = clampInt(_restorePage, 0, pages.length - 1);
        _pageNotifier.value = _page;
        _setupControllers();
      });
      unawaited(_historyRepo.record(manga, chapter, _page));
      _precacheAround(_page);
    } catch (e) {
      if (!mounted || token != _loadToken) return;
      setState(() => _error = e);
    }
  }

  void _setupControllers() {
    // On détruit l'ancien PageController APRÈS le prochain affichage (il est encore utilisé par l'ancien PageView).
    final old = _pageController;
    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    _pageController = null;

    _zoomed = false;
    _spreads = _buildSpreads(_count);
    if (_mode.isPaged) {
      _pageController = PageController(initialPage: _spreadIndexOfPage(_page));
    }
  }

  /// Regroupe les pages affichées ensemble (1 par écran, ou 2 en mode double page).
  List<List<int>> _buildSpreads(int count) {
    if (!_mode.isDouble) {
      return [
        for (var i = 0; i < count; i++) [i],
      ];
    }
    final result = <List<int>>[];
    if (count > 0) result.add([0]); // la première page (couverture) reste seule
    for (var i = 1; i < count; i += 2) {
      result.add(i + 1 < count ? [i, i + 1] : [i]);
    }
    return result;
  }

  int _spreadIndexOfPage(int page) {
    for (var s = 0; s < _spreads.length; s++) {
      if (_spreads[s].contains(page)) return s;
    }
    return 0;
  }

  // -------------------------------------------------------------- progression

  /// En mode webtoon, la page courante est celle qui couvre le haut de l'écran
  /// (celle dont le bord supérieur est visible), sinon la première encore
  /// visible. On repère aussi l'écran de fin de chapitre pour marquer « lu ».
  void _onPositionsChanged() {
    if (_mode != ReaderMode.webtoon || _pages == null) return;
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;
    int? current;
    var atEnd = false;
    for (final p in positions) {
      if (p.itemLeadingEdge <= 0 && p.itemTrailingEdge > 0) {
        current = p.index;
      }
      if (p.index >= _count && p.itemLeadingEdge < 1) {
        atEnd = true;
      }
    }
    // À défaut de page couvrant le haut, on prend la première visible.
    current ??= positions.map((p) => p.index).reduce((a, b) => a < b ? a : b);
    if (current >= _count) current = _count - 1;
    _setPage(current, reachedEnd: atEnd);
    _scheduleSave();
  }

  /// Modes horizontaux : le PageView nous dit sur quel "écran" on est.
  void _onSpreadChanged(int index) {
    if (_pages == null) return;
    if (index >= _spreads.length) {
      _setPage(_count - 1, reachedEnd: true);
      return;
    }
    final spread = _spreads[index];
    _setPage(spread.first, reachedEnd: spread.contains(_count - 1));
  }

  void _setPage(int page, {bool reachedEnd = false}) {
    if (_pages == null || !mounted) return;
    final p = clampInt(page, 0, _count - 1);
    final becameEnd = reachedEnd && !_reachedEnd;
    if (p == _page && !becameEnd) return;
    _page = p;
    if (reachedEnd) _reachedEnd = true;
    // Pas de setState : seul l'indicateur du bas écoute la page courante, le
    // contenu (liste d'images) n'est pas reconstruit pendant le défilement.
    _pageNotifier.value = p;
    _precacheAround(p);
    if (becameEnd) _saveProgress();
  }

  /// Sauvegarde différée (2 s) pendant le défilement, pour ne pas écrire à
  /// chaque pixel tout en gardant une position à jour.
  void _scheduleSave() {
    // Un seul minuteur réutilisé : `_onWebtoonScroll` est appelé à chaque image
    // affichée, créer un Timer à chaque fois allouait inutilement en continu.
    _saveDebounce ??= Timer(const Duration(seconds: 2), () {
      _saveDebounce = null;
      _saveProgress();
    });
  }

  Future<void> _saveProgress() async {
    final pages = _pages;
    if (pages == null || pages.isEmpty) return;
    final manga = widget.manga;
    final chapter = _chapter;
    await _progressRepo.savePosition(
      mangaKey: manga.key,
      chapterId: chapter.id,
      page: _page,
      read: _reachedEnd,
    );
    await _historyRepo.record(manga, chapter, _page);
  }

  /// Précharge les pages voisines pour éviter les temps d'attente.
  void _precacheAround(int page) {
    final pages = _pages;
    if (pages == null || !mounted) return;
    // On se limite aux voisines immédiates : décoder davantage d'images en même
    // temps (surtout des webtoons très hauts) saturait la mémoire et provoquait
    // des saccades.
    final offsets = _mode == ReaderMode.webtoon
        ? const [1, 2]
        : const [1, -1];
    for (final o in offsets) {
      final i = page + o;
      if (i < 0 || i >= pages.length) continue;
      final p = pages[i];
      final local = p.localPath;
      final ImageProvider provider = local != null
          ? FileImage(File(local))
          : CachedNetworkImageProvider(
              p.imageUrl,
              cacheKey: p.cacheKey,
              headers: ref.read(urlHeadersProvider)(p.imageUrl),
            );
      precacheImage(provider, context, onError: (_, _) {});
    }
  }

  // ------------------------------------------------------------------ actions

  void _toggleBars() {
    setState(() => _showBars = !_showBars);
    SystemChrome.setEnabledSystemUIMode(
      _showBars ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    );
  }

  /// Appui sur une page (modes horizontaux) : bords = tourner la page, centre = barres.
  void _onTapAt(Offset position) {
    final width = MediaQuery.of(context).size.width;
    final x = position.dx / width;
    if (x < 0.28) {
      _step(_mode.isRtl ? 1 : -1);
    } else if (x > 0.72) {
      _step(_mode.isRtl ? -1 : 1);
    } else {
      _toggleBars();
    }
  }

  void _step(int direction) {
    final controller = _pageController;
    if (controller == null || !controller.hasClients) return;
    final current = controller.page?.round() ?? 0;
    final target = current + direction;
    if (target < 0 || target > _spreads.length) return;
    controller.animateToPage(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _seekTo(int page) {
    final p = clampInt(page, 0, _count - 1);
    if (_mode == ReaderMode.webtoon) {
      if (!_itemScrollController.isAttached) return;
      _itemScrollController.jumpTo(index: p);
    } else {
      _pageController?.jumpToPage(_spreadIndexOfPage(p));
    }
  }

  Future<void> _changeChapter(int delta) async {
    final next = _chapterIndex + delta;
    if (next < 0 || next >= widget.chapters.length) return;
    await _saveProgress();
    if (!mounted) return;
    setState(() {
      _chapterIndex = next;
      _resetForLoad();
    });
    unawaited(_loadChapter());
  }

  Future<void> _pickMode() async {
    final picked = await showChoiceSheet<ReaderMode>(
      context,
      title: 'Mode de lecture',
      options: [for (final m in ReaderMode.values) (m, m.label)],
      selected: _mode,
    );
    if (picked == null || picked == _mode || !mounted) return;
    ref.read(settingsProvider.notifier).setReaderMode(picked);
    setState(() {
      _mode = picked;
      // Changement de mode en cours de chapitre : on repart de la page courante.
      _restorePage = _page;
      _setupControllers();
    });
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: _buildContent()),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _animatedBar(top: true, child: _topBar()),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _animatedBar(top: false, child: _bottomBar()),
          ),
        ],
      ),
    );
  }

  Widget _animatedBar({required bool top, required Widget child}) {
    return IgnorePointer(
      ignoring: !_showBars,
      child: AnimatedSlide(
        offset: _showBars ? Offset.zero : Offset(0, top ? -1 : 1),
        duration: const Duration(milliseconds: 180),
        child: AnimatedOpacity(
          opacity: _showBars ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: child,
        ),
      ),
    );
  }

  Widget _topBar() {
    return Material(
      color: Colors.black87,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kToolbarHeight,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.manga.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      _chapter.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.chrome_reader_mode_outlined,
                  color: Colors.white,
                ),
                tooltip: 'Mode de lecture',
                onPressed: _pickMode,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomBar() {
    final count = _count;
    final canSeek = count > 1;
    return Material(
      color: Colors.black87,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          // L'indicateur et le curseur écoutent [_pageNotifier] : le défilement
          // ne reconstruit donc que cette petite zone, pas tout le lecteur.
          child: ValueListenableBuilder<int>(
            valueListenable: _pageNotifier,
            builder: (context, page, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  count == 0 ? '' : '${page + 1} / $count',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.skip_previous,
                        color: Colors.white,
                      ),
                      tooltip: 'Chapitre précédent',
                      onPressed: _chapterIndex > 0
                          ? () => _changeChapter(-1)
                          : null,
                    ),
                    Expanded(
                      // En lecture droite → gauche, le curseur avance aussi vers la gauche.
                      child: Directionality(
                        textDirection: _mode.isRtl
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                        child: Slider(
                          value: canSeek ? page.toDouble() : 0,
                          min: 0,
                          max: canSeek ? (count - 1).toDouble() : 1,
                          divisions: canSeek ? count - 1 : null,
                          onChanged: canSeek
                              ? (v) {
                                  final p = v.round();
                                  if (p == page) return;
                                  _page = p;
                                  _pageNotifier.value = p;
                                  _seekTo(p);
                                }
                              : null,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next, color: Colors.white),
                      tooltip: 'Chapitre suivant',
                      onPressed: _chapterIndex < widget.chapters.length - 1
                          ? () => _changeChapter(1)
                          : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.white54, size: 48),
              const SizedBox(height: 12),
              Text(
                describeError(error),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  setState(_resetForLoad);
                  _loadChapter();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }
    final pages = _pages;
    if (pages == null) return const Center(child: CircularProgressIndicator());
    return _mode == ReaderMode.webtoon ? _webtoon(pages) : _pager(pages);
  }

  /// Défilement vertical continu (idéal pour les manhwas).
  ///
  /// [ScrollablePositionedList] suit la position par index de page : la page
  /// courante (barre du bas) reste donc exacte malgré les hauteurs variables des
  /// images, et l'ouverture repart précisément sur la page mémorisée grâce à
  /// [initialScrollIndex].
  Widget _webtoon(List<MangaPage> pages) {
    final height = MediaQuery.of(context).size.height;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _toggleBars,
      child: ScrollConfiguration(
        behavior: const _NoGlowScrollBehavior(),
        child: ScrollablePositionedList.builder(
          key: ValueKey('webtoon-$_chapterIndex'),
          itemScrollController: _itemScrollController,
          itemPositionsListener: _itemPositionsListener,
          initialScrollIndex: clampInt(_restorePage, 0, pages.length - 1),
          initialAlignment: 0,
          padding: EdgeInsets.zero,
          physics: const ClampingScrollPhysics(),
          itemCount: pages.length + 1, // +1 : l'écran de fin de chapitre
          itemBuilder: (context, i) {
            if (i >= pages.length) return _chapterEnd(height * 0.8);
            return _WebtoonPage(
              key: ValueKey('page-$i'),
              page: pages[i],
              semanticLabel: 'Page ${i + 1} sur ${pages.length}',
            );
          },
        ),
      ),
    );
  }

  /// Lecture horizontale (une page ou double page) avec zoom.
  Widget _pager(List<MangaPage> pages) {
    final rtl = _mode.isRtl;
    return PageView.builder(
      key: ValueKey('pager-$_chapterIndex-${_mode.name}'),
      controller: _pageController,
      reverse: rtl,
      // Quand l'image est zoomée, on désactive le balayage pour pouvoir la déplacer.
      physics: _zoomed
          ? const NeverScrollableScrollPhysics()
          : const PageScrollPhysics(),
      itemCount: _spreads.length + 1, // +1 : l'écran de fin de chapitre
      onPageChanged: _onSpreadChanged,
      itemBuilder: (context, i) {
        if (i >= _spreads.length) return _chapterEnd(null);
        final spread = _spreads[i];
        return ZoomableView(
          onTap: _onTapAt,
          onZoomChanged: (zoomed) {
            if (mounted && zoomed != _zoomed) setState(() => _zoomed = zoomed);
          },
          child: Row(
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            children: [
              for (final p in spread)
                Expanded(
                  child: _PageImage(
                    page: pages[p],
                    semanticLabel: 'Page ${p + 1} sur ${pages.length}',
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _chapterEnd(double? height) {
    final hasNext = _chapterIndex < widget.chapters.length - 1;
    final content = Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle_outline,
              color: Colors.white54,
              size: 56,
            ),
            const SizedBox(height: 12),
            Text(
              'Fin de « ${_chapter.displayTitle} »',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 20),
            if (hasNext)
              FilledButton.icon(
                onPressed: () => _changeChapter(1),
                icon: const Icon(Icons.skip_next),
                label: const Text('Chapitre suivant'),
              )
            else
              const Text(
                'Dernier chapitre disponible',
                style: TextStyle(color: Colors.white54),
              ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Retour'),
            ),
          ],
        ),
      ),
    );
    return height == null ? content : SizedBox(height: height, child: content);
  }
}

/// Comportement de défilement sans sur-défilement (ni halo ni rebond) : le
/// contenu ne « remonte » jamais tout seul en haut.
class _NoGlowScrollBehavior extends ScrollBehavior {
  const _NoGlowScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();
}

/// Une page de webtoon : réserve immédiatement sa hauteur définitive dès que le
/// ratio de l'image est connu (résolu pendant que la page est encore hors
/// écran). Résultat : aucune page ne change de taille une fois affichée, donc
/// plus de saut de défilement quand l'image finit de charger.
class _WebtoonPage extends ConsumerStatefulWidget {
  const _WebtoonPage({super.key, required this.page, this.semanticLabel});

  final MangaPage page;
  final String? semanticLabel;

  @override
  ConsumerState<_WebtoonPage> createState() => _WebtoonPageState();
}

class _WebtoonPageState extends ConsumerState<_WebtoonPage> {
  double? _ratio; // largeur / hauteur
  ImageStream? _stream;
  ImageStreamListener? _listener;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _resolveRatio();
  }

  ImageProvider _provider() {
    final page = widget.page;
    final width =
        (MediaQuery.of(context).size.width *
                MediaQuery.of(context).devicePixelRatio)
            .round()
            .clamp(1, 4096);
    final local = page.localPath;
    final ImageProvider base = local != null
        ? FileImage(File(local))
        : CachedNetworkImageProvider(
            page.imageUrl,
            cacheKey: page.cacheKey,
            headers: ref.read(urlHeadersProvider)(page.imageUrl),
          );
    // On décode à la largeur de l'écran : le ratio est conservé, la mémoire
    // reste bornée, et le cache d'images est partagé avec l'affichage.
    return ResizeImage(base, width: width);
  }

  void _resolveRatio() {
    final stream = _provider().resolve(createLocalImageConfiguration(context));
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        if (!mounted) return;
        final w = info.image.width;
        final h = info.image.height;
        if (w > 0 && h > 0) setState(() => _ratio = w / h);
      },
      onError: (_, _) => stream.removeListener(listener),
    );
    stream.addListener(listener);
    _stream = stream;
    _listener = listener;
  }

  @override
  void dispose() {
    final stream = _stream;
    final listener = _listener;
    if (stream != null && listener != null) stream.removeListener(listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _PageImage(
      page: widget.page,
      fit: BoxFit.fitWidth,
      fullWidth: true,
      semanticLabel: widget.semanticLabel,
    );
    final ratio = _ratio;
    if (ratio == null) {
      // Hauteur provisoire : le haut de la page reste ancré, seul le bas
      // s'ajuste — aucun saut visible le temps que l'image se charge.
      return SizedBox(
        width: double.infinity,
        height: MediaQuery.of(context).size.width * 1.4,
        child: image,
      );
    }
    return AspectRatio(aspectRatio: ratio, child: image);
  }
}

/// Une image de page : depuis le disque (chapitre téléchargé) ou depuis internet (avec cache).
///
/// Aucun indicateur de chargement (pas de roue) : l'image apparaît en fondu dès
/// qu'elle est prête. En mode webtoon, une hauteur est réservée pour éviter que
/// le contenu ne « saute » pendant le chargement.
class _PageImage extends ConsumerStatefulWidget {
  const _PageImage({
    required this.page,
    this.fit = BoxFit.contain,
    this.fullWidth = false,
    this.semanticLabel,
  });

  final MangaPage page;
  final BoxFit fit;
  final String? semanticLabel;

  /// Vrai en mode webtoon : l'image occupe toute la largeur.
  final bool fullWidth;

  @override
  ConsumerState<_PageImage> createState() => _PageImageState();
}

class _PageImageState extends ConsumerState<_PageImage> {
  int _attempt = 0;

  Widget _placeholder() {
    if (!widget.fullWidth) return const SizedBox.shrink();
    return const SizedBox(width: double.infinity, height: 300);
  }

  Widget _errorWidget() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.broken_image_outlined,
            color: Colors.white54,
            size: 40,
          ),
          TextButton.icon(
            onPressed: _retry,
            icon: const Icon(Icons.refresh),
            label: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }

  Future<void> _retry() async {
    final page = widget.page;
    await CachedNetworkImage.evictFromCache(
      page.imageUrl,
      cacheKey: page.cacheKey,
    );
    if (mounted) setState(() => _attempt++);
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.page;
    final fullWidth = widget.fullWidth;
    final local = page.localPath;
    // Décoder à la largeur de l'écran : les pages (surtout les webtoons très
    // hauts) ne sont plus décodées à leur taille native, ce qui allège
    // énormément la mémoire et accélère l'affichage.
    final cacheWidth =
        (MediaQuery.of(context).size.width *
                MediaQuery.of(context).devicePixelRatio)
            .round()
            .clamp(1, 4096);
    final Widget image;
    if (local != null) {
      image = Image.file(
        File(local),
        width: fullWidth ? double.infinity : null,
        fit: widget.fit,
        cacheWidth: cacheWidth,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSync) {
          if (wasSync || frame != null) return child;
          return _placeholder();
        },
        errorBuilder: (_, _, _) => _errorWidget(),
      );
    } else {
      image = CachedNetworkImage(
        key: ValueKey('${page.imageUrl}#$_attempt'),
        imageUrl: page.imageUrl,
        cacheKey: page.cacheKey,
        httpHeaders: ref.watch(urlHeadersProvider)(page.imageUrl),
        width: fullWidth ? double.infinity : null,
        fit: widget.fit,
        memCacheWidth: cacheWidth,
        fadeInDuration: const Duration(milliseconds: 120),
        fadeOutDuration: Duration.zero,
        placeholder: (context, url) => _placeholder(),
        errorWidget: (context, url, error) => _errorWidget(),
      );
    }
    final label = widget.semanticLabel;
    if (label == null) return image;
    return Semantics(image: true, label: label, child: image);
  }
}
