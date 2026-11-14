import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/sources/manga_source.dart';
import 'catalogue_screen.dart';

/// Liste des sources, avec recherche et épinglage des favorites.
class SourcesScreen extends ConsumerStatefulWidget {
  const SourcesScreen({super.key});

  @override
  ConsumerState<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends ConsumerState<SourcesScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final sources = ref.watch(sourcesProvider);
    final pinned = ref.watch(settingsProvider.select((s) => s.pinnedSources));

    final filtered = sources
        .where((s) => s.name.toLowerCase().contains(_query))
        .toList();
    final pinnedList = filtered.where((s) => pinned.contains(s.id)).toList();
    final others = filtered.where((s) => !pinned.contains(s.id)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Explorer')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Rechercher une source',
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(28)),
                ),
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                if (pinnedList.isNotEmpty) const _SectionHeader('Épinglées'),
                for (final s in pinnedList) _tile(s, true),
                if (others.isNotEmpty) const _SectionHeader('Sources'),
                for (final s in others) _tile(s, false),
                if (filtered.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('Aucune source trouvée')),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(MangaSource source, bool isPinned) {
    return ListTile(
      leading: CircleAvatar(child: Text(source.name[0].toUpperCase())),
      title: Text(source.name),
      subtitle: Text(
        source.description,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        icon: Icon(isPinned ? Icons.push_pin : Icons.push_pin_outlined),
        tooltip: isPinned ? 'Désépingler' : 'Épingler',
        onPressed: () =>
            ref.read(settingsProvider.notifier).togglePinned(source.id),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CatalogueScreen(source: source),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}
