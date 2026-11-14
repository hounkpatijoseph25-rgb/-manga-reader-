import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../data/repositories/settings_repository.dart';
import '../../shared/widgets/choice_sheet.dart';
import '../downloads/downloads_provider.dart';
import 'storage_info_provider.dart';

/// Réglages : apparence, lecteur, langue, stockage, à propos.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final storage = ref.watch(storageInfoProvider);

    String sizeText(int Function(StorageInfo info) pick) => storage.when(
      data: (info) => formatBytes(pick(info)),
      loading: () => 'Calcul…',
      error: (_, __) => 'Inconnu',
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres')),
      body: ListView(
        children: [
          // ------------------------------------------------------ Apparence
          const _SectionTitle('Apparence'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('Système'),
                  icon: Icon(Icons.brightness_auto),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('Clair'),
                  icon: Icon(Icons.light_mode),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('Sombre'),
                  icon: Icon(Icons.dark_mode),
                ),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (v) => notifier.setThemeMode(v.first),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (var i = 0; i < kSeedColors.length; i++)
                  GestureDetector(
                    onTap: () => notifier.setSeedIndex(i),
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: kSeedColors[i],
                      child: settings.seedIndex == i
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 18,
                            )
                          : null,
                    ),
                  ),
              ],
            ),
          ),

          // --------------------------------------------------------- Lecteur
          const _SectionTitle('Lecteur'),
          ListTile(
            leading: const Icon(Icons.chrome_reader_mode_outlined),
            title: const Text('Mode de lecture par défaut'),
            subtitle: Text(settings.readerMode.label),
            onTap: () async {
              final picked = await showChoiceSheet<ReaderMode>(
                context,
                title: 'Mode de lecture par défaut',
                options: [for (final m in ReaderMode.values) (m, m.label)],
                selected: settings.readerMode,
              );
              if (picked != null) notifier.setReaderMode(picked);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.data_saver_on_outlined),
            title: const Text('Économie de données'),
            subtitle: const Text('Images compressées (MangaDex uniquement)'),
            value: settings.dataSaver,
            onChanged: notifier.setDataSaver,
          ),

          // --------------------------------------------------------- Contenu
          const _SectionTitle('Contenu'),
          ListTile(
            leading: const Icon(Icons.translate),
            title: const Text('Langue des chapitres'),
            subtitle: Text(
              kLanguages[settings.contentLanguage] ?? settings.contentLanguage,
            ),
            onTap: () async {
              final picked = await showChoiceSheet<String>(
                context,
                title: 'Langue des chapitres',
                options: [for (final e in kLanguages.entries) (e.key, e.value)],
                selected: settings.contentLanguage,
              );
              if (picked != null) notifier.setContentLanguage(picked);
            },
          ),

          // --------------------------------------------- Stockage / téléchargements
          const _SectionTitle('Stockage et téléchargements'),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('Cache des images'),
            subtitle: Text(sizeText((i) => i.cacheBytes)),
            trailing: FilledButton.tonal(
              onPressed: () => _clearCache(context, ref),
              child: const Text('Vider le cache'),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.download_done),
            title: const Text('Chapitres téléchargés'),
            subtitle: Text(sizeText((i) => i.downloadBytes)),
            trailing: TextButton(
              onPressed: () => _clearDownloads(context, ref),
              child: const Text('Tout supprimer'),
            ),
          ),

          // ---------------------------------------------------------- À propos
          const _SectionTitle('À propos'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text(AppConstants.appName),
            subtitle: const Text('Version ${AppConstants.version}'),
            onTap: () => showAboutDialog(
              context: context,
              applicationName: AppConstants.appName,
              applicationVersion: AppConstants.version,
              children: const [
                SizedBox(height: 12),
                Text(
                  'Lecteur de manga / manhwa inspiré de Mihon et Tachiyomi. '
                  'Projet personnel d\'apprentissage en Flutter.',
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.system_update_alt),
            title: const Text('Mises à jour'),
            subtitle: const Text(
              "Pas de serveur de mises à jour pour l'instant",
            ),
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  "Aucun serveur de mises à jour n'est configuré : "
                  "l'application se met à jour en la recompilant.",
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _clearCache(BuildContext context, WidgetRef ref) async {
    await DefaultCacheManager().emptyCache();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    ref.invalidate(storageInfoProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Cache vidé')));
    }
  }

  Future<void> _clearDownloads(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer tous les téléchargements ?'),
        content: const Text(
          'Tu devras les retélécharger pour les lire hors connexion.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(downloadServiceProvider).clearAll();
    ref.read(downloadsProvider.notifier).clearDone();
    ref.invalidate(storageInfoProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Téléchargements supprimés')),
      );
    }
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}
