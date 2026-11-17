import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/background_updates.dart';
import '../../core/constants.dart';
import '../../core/notifications.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/files.dart';
import '../../core/utils/format.dart';
import '../../data/repositories/settings_repository.dart';
import '../../shared/widgets/choice_sheet.dart';
import '../browse/local_library.dart';
import '../downloads/downloads_screen.dart';
import '../library/library_updater.dart';
import 'storage_info_provider.dart';

/// Réglages : apparence, lecteur, langue, stockage, à propos.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final storage = ref.watch(storageInfoProvider);
    // La boîte de veille change à chaque passage : l'écran se rafraîchit.
    ref.watch(pendingUpdatesProvider);
    final lastRun = ref.read(updatesRepositoryProvider).lastRun();

    String sizeText(int Function(StorageInfo info) pick) => storage.when(
      data: (info) => formatBytes(pick(info)),
      loading: () => 'Calcul…',
      error: (_, _) => 'Inconnu',
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
          SwitchListTile(
            secondary: const Icon(Icons.screen_lock_portrait_outlined),
            title: const Text("Garder l'écran allumé"),
            subtitle: const Text("Pendant la lecture d'un chapitre"),
            value: settings.keepScreenOn,
            onChanged: notifier.setKeepScreenOn,
          ),
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('Luminosité du lecteur'),
            subtitle: Text(
              settings.readerBrightness < 0
                  ? 'Luminosité du système'
                  : '${(settings.readerBrightness * 100).round()} %',
            ),
            onTap: () => _pickBrightness(context, ref),
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

          // -------------------------------------------------------- Nouveautés
          const _SectionTitle('Nouveautés'),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('Vérification automatique'),
            subtitle: Text(
              settings.updatesIntervalHours <= 0
                  ? 'Désactivée'
                  : 'Toutes les ${settings.updatesIntervalHours} heures',
            ),
            onTap: () async {
              final picked = await showChoiceSheet<int>(
                context,
                title: 'Vérification automatique',
                options: const [
                  (0, 'Désactivée'),
                  (1, 'Toutes les heures'),
                  (3, 'Toutes les 3 heures'),
                  (6, 'Toutes les 6 heures'),
                  (12, 'Toutes les 12 heures'),
                  (24, 'Une fois par jour'),
                ],
                selected: settings.updatesIntervalHours,
              );
              if (picked == null ||
                  picked == settings.updatesIntervalHours) {
                return;
              }
              notifier.setUpdatesIntervalHours(picked);
              await applyUpdatesSchedule(picked);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('Notifications de nouveaux chapitres'),
            subtitle: const Text(
              'Prévenir quand la veille découvre des nouveautés',
            ),
            value: settings.notificationsEnabled,
            onChanged: (value) async {
              notifier.setNotificationsEnabled(value);
              if (value) await NotificationService.requestPermission();
            },
          ),
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Dernière vérification'),
            subtitle: Text(
              lastRun == null
                  ? 'Pas encore vérifié'
                  : formatRelative(lastRun),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.system_update_alt),
            title: const Text('Vérifier maintenant'),
            subtitle: const Text(
              'Chercher les nouveaux chapitres des mangas suivis',
            ),
            onTap: () => _checkUpdates(context, ref),
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
            title: const Text('Téléchargements'),
            subtitle: Text(
              '${ref.watch(downloadsListProvider).value?.length ?? 0} chapitre(s) • '
              '${sizeText((i) => i.downloadBytes)}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const DownloadsScreen(),
              ),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.no_adult_content),
            title: const Text('Contenu réservé aux adultes'),
            subtitle: const Text('Afficher les sources +18 (désactivé par défaut)'),
            value: settings.showNsfw,
            onChanged: notifier.setShowNsfw,
          ),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Dossier des téléchargements'),
            subtitle: Text(
              settings.downloadsDir.isEmpty
                  ? "Dossier interne de l'application"
                  : settings.downloadsDir,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: settings.downloadsDir.isEmpty
                ? FilledButton.tonal(
                    onPressed: () => _pickDownloadsDir(context, ref),
                    child: const Text('Choisir'),
                  )
                : IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Revenir au dossier interne',
                    onPressed: () => _resetDownloadsDir(context, ref),
                  ),
            onTap: () => _pickDownloadsDir(context, ref),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.signal_cellular_alt),
            title: const Text('Télécharger en données mobiles'),
            subtitle: const Text(
              'Désactivé : la file attend une connexion Wi-Fi',
            ),
            value: settings.downloadsOnMobileData,
            onChanged: notifier.setDownloadsOnMobileData,
          ),

          // ------------------------------------------------- bibliothèque locale
          const _SectionTitle('Bibliothèque locale'),
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: const Text('Dossier des mangas'),
            subtitle: Text(
              settings.localRoot.isEmpty
                  ? 'Aucun dossier importé'
                  : settings.localRoot,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: settings.localRoot.isEmpty
                ? FilledButton.tonal(
                    onPressed: () => _pickLocalFolder(context, ref),
                    child: const Text('Choisir'),
                  )
                : IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Retirer ce dossier',
                    onPressed: () => forgetLocalRoot(context, ref),
                  ),
            onTap: () => _pickLocalFolder(context, ref),
          ),

          // ------------------------------------------ Sauvegarde et restauration
          const _SectionTitle('Sauvegarde et restauration'),
          ListTile(
            leading: const Icon(Icons.save_alt),
            title: const Text('Exporter la sauvegarde'),
            subtitle: const Text(
              'Bibliothèque, progression, historique et réglages',
            ),
            onTap: () => _exportBackup(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('Importer une sauvegarde'),
            subtitle: const Text('Remplace les données actuelles'),
            onTap: () => _importBackup(context, ref),
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
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      child: Image(
                        image: AssetImage('assets/images/logo.png'),
                        width: 56,
                        height: 56,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Lecteur de manga / manhwa, projet personnel écrit '
                        'en Flutter.',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// Lance la veille des mangas suivis et affiche le résultat.
  Future<void> _checkUpdates(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final report = await ref.read(libraryUpdaterProvider.notifier).refresh();
    if (!context.mounted) return;
    final lines = <String>[
      if (report.newChapters > 0)
        '${report.newChapters} nouveau(x) chapitre(s) : '
            '${report.titles.join(', ')}'
      else if (report.checked > 0)
        'Aucun nouveau chapitre (${report.checked} manga(s) vérifié(s))'
      else
        'Aucun manga à vérifier : ajoute des mangas à ta bibliothèque',
      if (report.failed > 0)
        '${report.failed} manga(s) injoignable(s) cette fois-ci',
    ];
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(lines.join(' · '))));
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

  /// Choisit (ou change) le dossier de la bibliothèque locale.
  Future<void> _pickLocalFolder(BuildContext context, WidgetRef ref) =>
      pickLocalRoot(context, ref);

  /// Choisit le dossier où enregistrer les chapitres téléchargés.
  Future<void> _pickDownloadsDir(BuildContext context, WidgetRef ref) async {
    final path = await pickFolder();
    if (path == null) return;
    ref.read(settingsProvider.notifier).setDownloadsDir(path);
    ref.invalidate(storageInfoProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Dossier : $path')));
    }
  }

  /// Revient au dossier interne de l'application.
  void _resetDownloadsDir(BuildContext context, WidgetRef ref) {
    ref.read(settingsProvider.notifier).setDownloadsDirMode('internal');
    ref.invalidate(storageInfoProvider);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text("Dossier interne de l'application")),
      );
  }

  /// Choisit la luminosité appliquée par le lecteur (`-1` = système).
  Future<void> _pickBrightness(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(settingsProvider.notifier);
    var value = ref.read(settingsProvider).readerBrightness;
    final chosen = await showDialog<double>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Luminosité du lecteur'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Slider(
                value: value < 0 ? 0.5 : value,
                onChanged: (v) => setLocal(() => value = v),
              ),
              Text(
                value < 0
                    ? 'Luminosité du système'
                    : '${(value * 100).round()} %',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(-1.0),
              child: const Text('Système'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(value < 0 ? 0.5 : value),
              child: const Text('Valider'),
            ),
          ],
        ),
      ),
    );
    if (chosen != null) notifier.setReaderBrightness(chosen);
  }

  /// Enregistre la base locale dans un fichier JSON choisi par l'utilisateur.
  Future<void> _exportBackup(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final json = ref.read(backupServiceProvider).encode();
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    String? path;
    try {
      path = await FilePicker.platform.saveFile(
        dialogTitle: 'Enregistrer la sauvegarde',
        fileName: 'manga_reader_sauvegarde_$stamp.json',
        bytes: utf8.encode(json),
      );
    } catch (_) {
      path = null;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            path == null ? 'Export annulé' : 'Sauvegarde enregistrée',
          ),
        ),
      );
  }

  /// Restaure la base locale depuis un fichier JSON choisi par l'utilisateur.
  Future<void> _importBackup(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Choisir une sauvegarde',
        withData: true,
      );
    } catch (_) {
      result = null;
    }
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.single.bytes;
    if (bytes == null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Fichier illisible')));
      return;
    }
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restaurer la sauvegarde ?'),
        content: const Text(
          'La bibliothèque, la progression, l\'historique et les réglages '
          'actuels seront remplacés par le contenu du fichier.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restaurer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      await ref.read(backupServiceProvider).restore(decoded);
      ref.invalidate(settingsProvider);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Sauvegarde restaurée')));
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Sauvegarde invalide ou illisible')),
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
