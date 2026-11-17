import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../browse/sources_screen.dart';
import '../history/history_screen.dart';
import '../library/library_screen.dart';
import '../settings/settings_screen.dart';
import '../upcoming/upcoming_screen.dart';

/// Barre de navigation du bas : Bibliothèque / À venir / Historique /
/// Explorer / Réglages.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  /// Onglets déjà affichés au moins une fois.
  ///
  /// `IndexedStack` construit tous ses enfants dès le démarrage : l'onglet
  /// « À venir » parcourait donc tout le cache de chapitres de la bibliothèque
  /// avant même le premier affichage. On ne construit un écran qu'à sa première
  /// visite (l'état reste ensuite conservé).
  final Set<int> _built = <int>{0};

  static const _pages = <Widget>[
    LibraryScreen(),
    UpcomingScreen(),
    HistoryScreen(),
    SourcesScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    // Chapitres repérés par la veille et pas encore consultés.
    final pending = ref.watch(pendingUpdatesCountProvider);

    Widget libraryIcon(IconData icon) => Badge.count(
      count: pending,
      isLabelVisible: pending > 0,
      child: Icon(icon),
    );

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          for (var i = 0; i < _pages.length; i++)
            _built.contains(i) ? _pages[i] : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() {
          _built.add(i);
          _index = i;
        }),
        destinations: [
          NavigationDestination(
            icon: libraryIcon(Icons.collections_bookmark_outlined),
            selectedIcon: libraryIcon(Icons.collections_bookmark),
            label: 'Bibliothèque',
          ),
          const NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'À venir',
          ),
          const NavigationDestination(
            icon: Icon(Icons.history),
            label: 'Historique',
          ),
          const NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Explorer',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Réglages',
          ),
        ],
      ),
    );
  }
}
