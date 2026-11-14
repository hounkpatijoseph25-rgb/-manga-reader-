import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../browse/sources_screen.dart';
import '../history/history_screen.dart';
import '../library/library_screen.dart';
import '../settings/settings_screen.dart';

/// Barre de navigation du bas : Bibliothèque / Historique / Explorer / Réglages.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  static const _pages = <Widget>[
    LibraryScreen(),
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
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
            icon: libraryIcon(Icons.collections_bookmark_outlined),
            selectedIcon: libraryIcon(Icons.collections_bookmark),
            label: 'Bibliothèque',
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
