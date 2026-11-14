import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/sources/manga_source.dart';
import '../../shared/widgets/cover_image.dart';
import 'catalogue_screen.dart';
import 'global_search_screen.dart';
import 'local_library.dart';

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
      appBar: AppBar(
        title: const Text('Explorer'),
        actions: [
          IconButton(
            tooltip: 'Recherche globale',
            icon: const Icon(Icons.travel_explore),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const GlobalSearchScreen(),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Importer un dossier local',
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: _importLocal,
          ),
        ],
      ),
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
                if (filtered.isNotEmpty) _cloudflareNote(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _importLocal() async {
    await pickLocalRoot(context, ref);
    if (mounted) setState(() {});
  }

  Future<void> _forgetLocal() async {
    forgetLocalRoot(context, ref);
    if (mounted) setState(() {});
  }

  /// Deux sites très demandés sont protégés par Cloudflare : inutile de laisser
  /// croire qu'ils sont disponibles, on l'explique directement dans la liste.
  Widget _cloudflareNote() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, size: 18, color: scheme.outline),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "ToonFR et Mangafire sont protégés par Cloudflare : ces sources "
              "ne sont pas encore disponibles dans l'application.",
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.outline),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(MangaSource source, bool isPinned) {
    final icon = source.iconUrl;
    final isLocal = source.id == 'local';
    final hasFolder =
        isLocal && ref.read(settingsProvider).localRoot.isNotEmpty;
    return ListTile(
      leading: icon == null
          ? CircleAvatar(child: Text(source.name[0].toUpperCase()))
          : ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 40,
                height: 40,
                child: CoverImage(url: icon),
              ),
            ),
      title: Text(source.name),
      subtitle: Text(
        source.description,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: isLocal
          ? PopupMenuButton<String>(
              tooltip: 'Gérer le dossier local',
              onSelected: (value) {
                if (value == 'folder') _importLocal();
                if (value == 'forget') _forgetLocal();
                if (value == 'pin') {
                  ref.read(settingsProvider.notifier).togglePinned(source.id);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'folder',
                  child: Text(
                    hasFolder ? 'Changer de dossier' : 'Choisir un dossier',
                  ),
                ),
                if (hasFolder)
                  const PopupMenuItem(
                    value: 'forget',
                    child: Text('Oublier le dossier'),
                  ),
                PopupMenuItem(
                  value: 'pin',
                  child: Text(isPinned ? 'Désépingler' : 'Épingler'),
                ),
              ],
            )
          : IconButton(
              icon: Icon(isPinned ? Icons.push_pin : Icons.push_pin_outlined),
              tooltip: isPinned ? 'Désépingler' : 'Épingler',
              onPressed: () =>
                  ref.read(settingsProvider.notifier).togglePinned(source.id),
            ),
      onTap: () {
        if (isLocal && !hasFolder) {
          _importLocal();
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CatalogueScreen(source: source),
          ),
        );
      },
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
