import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

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
/// - La dernière page lue est enregistrée quand on quitte le chapitre.
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

  PageController? _pageController;
  ItemScrollController _itemScroll = ItemScrollController();
  ItemPositionsListener _itemPositions = ItemPositionsListener.create();
  List<List<int>> _spreads = const [];

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
    _itemPositions.itemPositions.addListener(_onPositions);
    _loadChapter();
  }

  @override
  void dispose() {
    _saveProgress(); // sauvegarde de la dernière page lue
    WidgetsBinding.instance.removeObserver(this);
    _itemPositions.itemPositions.removeListener(_onPositions);
    _pageController?.dispose();
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
      if (pages.isEmpty)
        throw StateError('Ce chapitre ne contient aucune page.');

      // Reprise à la dernière page lue (sauf si le chapitre est déjà terminé).
      final progress = _progressRepo.get(manga.key);
      final start = progress.isRead(chapter.id)
          ? 0
          : progress.pageOf(chapter.id);

      setState(() {
        _pages = pages;
        _page = clampInt(start, 0, pages.length - 1);
        _setupControllers();
      });
      _historyRepo.record(manga, chapter, _page);
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

    _itemPositions.itemPositions.removeListener(_onPositions);
    _itemScroll = ItemScrollController();
    _itemPositions = ItemPositionsListener.create();
    _itemPositions.itemPositions.addListener(_onPositions);

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

  /// Mode webtoon : on déduit la page courante des éléments visibles.
  void _onPositions() {
    if (_mode != ReaderMode.webtoon || _pages == null) return;
    final positions = _itemPositions.itemPositions.value;
    var first = -1;
    var last = 0;
    for (final p in positions) {
      if (p.itemTrailingEdge <= 0.02) continue;
      if (first == -1 || p.index < first) first = p.index;
      if (p.index > last) last = p.index;
    }
    if (first == -1) return;
    _setPage(first, reachedEnd: last >= _count - 1);
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
    setState(() {
      _page = p;
      if (reachedEnd) _reachedEnd = true;
    });
    _precacheAround(p);
    if (becameEnd) _saveProgress();
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
    for (final offset in const [1, 2, 3, -1]) {
      final i = page + offset;
      if (i < 0 || i >= pages.length) continue;
      final p = pages[i];
      final local = p.localPath;
      final ImageProvider provider = local != null
          ? FileImage(File(local))
          : CachedNetworkImageProvider(p.imageUrl, cacheKey: p.cacheKey);
      precacheImage(provider, context, onError: (_, __) {});
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
      _itemScroll.jumpTo(index: p);
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
    _loadChapter();
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                count == 0 ? '' : '${_page + 1} / $count',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.skip_previous, color: Colors.white),
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
                        value: canSeek ? _page.toDouble() : 0,
                        min: 0,
                        max: canSeek ? (count - 1).toDouble() : 1,
                        divisions: canSeek ? count - 1 : null,
                        onChanged: canSeek
                            ? (v) {
                                final p = v.round();
                                if (p == _page) return;
                                setState(() => _page = p);
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
  Widget _webtoon(List<MangaPage> pages) {
    final height = MediaQuery.of(context).size.height;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _toggleBars,
      child: ScrollablePositionedList.builder(
        key: ValueKey('webtoon-$_chapterIndex'),
        itemCount: pages.length + 1, // +1 : l'écran de fin de chapitre
        initialScrollIndex: _page,
        itemScrollController: _itemScroll,
        itemPositionsListener: _itemPositions,
        itemBuilder: (context, i) {
          if (i >= pages.length) return _chapterEnd(height * 0.8);
          return _PageImage(
            page: pages[i],
            fit: BoxFit.fitWidth,
            placeholderHeight: height * 0.6,
          );
        },
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
                Expanded(child: _PageImage(page: pages[p])),
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

/// Une image de page : depuis le disque (chapitre téléchargé) ou depuis internet (avec cache).
class _PageImage extends StatefulWidget {
  const _PageImage({
    required this.page,
    this.fit = BoxFit.contain,
    this.placeholderHeight,
  });

  final MangaPage page;
  final BoxFit fit;

  /// Défini en mode webtoon : hauteur réservée pendant le chargement.
  final double? placeholderHeight;

  @override
  State<_PageImage> createState() => _PageImageState();
}

class _PageImageState extends State<_PageImage> {
  int _attempt = 0;

  Widget _boxed(Widget child) {
    final height = widget.placeholderHeight;
    return height == null
        ? Center(child: child)
        : SizedBox(
            height: height,
            child: Center(child: child),
          );
  }

  Widget _errorWidget() {
    return _boxed(
      Column(
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
    final fullWidth = widget.placeholderHeight != null;
    final local = page.localPath;
    if (local != null) {
      return Image.file(
        File(local),
        width: fullWidth ? double.infinity : null,
        fit: widget.fit,
        errorBuilder: (_, __, ___) => _errorWidget(),
      );
    }
    return CachedNetworkImage(
      key: ValueKey('${page.imageUrl}#$_attempt'),
      imageUrl: page.imageUrl,
      cacheKey: page.cacheKey,
      width: fullWidth ? double.infinity : null,
      fit: widget.fit,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      progressIndicatorBuilder: (context, url, progress) =>
          _boxed(CircularProgressIndicator(value: progress.progress)),
      errorWidget: (context, url, error) => _errorWidget(),
    );
  }
}
