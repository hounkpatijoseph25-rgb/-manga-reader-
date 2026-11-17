import 'package:flutter/material.dart' show ThemeMode;
import 'package:hive_flutter/hive_flutter.dart';

/// Modes de lecture disponibles dans le lecteur.
enum ReaderMode { webtoon, leftToRight, rightToLeft, doubleRtl, doubleLtr }

extension ReaderModeX on ReaderMode {
  String get label => switch (this) {
    ReaderMode.webtoon => 'Vertical continu (Webtoon)',
    ReaderMode.leftToRight => 'Horizontal (gauche → droite)',
    ReaderMode.rightToLeft => 'Horizontal (droite → gauche)',
    ReaderMode.doubleRtl => 'Double page (droite → gauche)',
    ReaderMode.doubleLtr => 'Double page (gauche → droite)',
  };

  bool get isRtl =>
      this == ReaderMode.rightToLeft || this == ReaderMode.doubleRtl;

  bool get isDouble =>
      this == ReaderMode.doubleRtl || this == ReaderMode.doubleLtr;

  bool get isPaged => this != ReaderMode.webtoon;
}

/// Langues de chapitres proposées (codes MangaDex).
const Map<String, String> kLanguages = {
  'fr': 'Français',
  'en': 'English',
  'es': 'Español',
  'pt-br': 'Português (Brésil)',
  'it': 'Italiano',
  'de': 'Deutsch',
};

class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.seedIndex = 0,
    this.readerMode = ReaderMode.webtoon,
    this.contentLanguage = 'fr',
    this.dataSaver = true,
    this.libraryGrid = true,
    this.pinnedSources = const [],
    this.localRoot = '',
    this.localCovers = const {},
    this.updatesIntervalHours = 6,
    this.downloadsDir = '',
    this.showNsfw = false,
    this.downloadsDirMode = 'unset',
    this.downloadsOnMobileData = false,
    this.notificationsEnabled = true,
    this.keepScreenOn = true,
    this.readerBrightness = -1,
  });

  final ThemeMode themeMode;
  final int seedIndex;
  final ReaderMode readerMode;
  final String contentLanguage;
  final bool dataSaver;
  final bool libraryGrid;
  final List<String> pinnedSources;

  /// Dossier de la bibliothèque locale (vide = aucun dossier importé).
  final String localRoot;

  /// Images de présentation choisies à la main : `dossier du manga → image`.
  final Map<String, String> localCovers;

  /// Fréquence de la veille des nouveaux chapitres, en heures
  /// (`0` = vérification automatique désactivée).
  final int updatesIntervalHours;

  /// Dossier de destination des chapitres téléchargés (vide = dossier interne).
  final String downloadsDir;

  /// Afficher les sources réservées aux adultes.
  final bool showNsfw;

  /// Choix du dossier de téléchargements : `unset`, `internal` ou `custom`.
  final String downloadsDirMode;

  /// Autoriser les téléchargements en données mobiles (désactivé par défaut :
  /// la file attend le Wi-Fi).
  final bool downloadsOnMobileData;

  /// Prévenir par une notification quand la veille découvre des chapitres.
  final bool notificationsEnabled;

  /// Garder l'écran allumé pendant la lecture d'un chapitre.
  final bool keepScreenOn;

  /// Luminosité du lecteur (`0..1`) ; `-1` = luminosité du système.
  final double readerBrightness;

  AppSettings copyWith({
    ThemeMode? themeMode,
    int? seedIndex,
    ReaderMode? readerMode,
    String? contentLanguage,
    bool? dataSaver,
    bool? libraryGrid,
    List<String>? pinnedSources,
    String? localRoot,
    Map<String, String>? localCovers,
    int? updatesIntervalHours,
    String? downloadsDir,
    bool? showNsfw,
    String? downloadsDirMode,
    bool? downloadsOnMobileData,
    bool? notificationsEnabled,
    bool? keepScreenOn,
    double? readerBrightness,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      seedIndex: seedIndex ?? this.seedIndex,
      readerMode: readerMode ?? this.readerMode,
      contentLanguage: contentLanguage ?? this.contentLanguage,
      dataSaver: dataSaver ?? this.dataSaver,
      libraryGrid: libraryGrid ?? this.libraryGrid,
      pinnedSources: pinnedSources ?? this.pinnedSources,
      localRoot: localRoot ?? this.localRoot,
      localCovers: localCovers ?? this.localCovers,
      updatesIntervalHours:
          updatesIntervalHours ?? this.updatesIntervalHours,
      downloadsDir: downloadsDir ?? this.downloadsDir,
      showNsfw: showNsfw ?? this.showNsfw,
      downloadsDirMode: downloadsDirMode ?? this.downloadsDirMode,
      downloadsOnMobileData:
          downloadsOnMobileData ?? this.downloadsOnMobileData,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      readerBrightness: readerBrightness ?? this.readerBrightness,
    );
  }
}

class SettingsRepository {
  SettingsRepository(this._box);

  final Box<dynamic> _box;

  T _pick<T extends Enum>(List<T> values, Object? name, T fallback) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return fallback;
  }

  AppSettings load() {
    final pinned = _box.get('pinned');
    final downloadsDir = (_box.get('downloadsDir') as String?) ?? '';
    final rawMode = _box.get('downloadsDirMode') as String?;
    var downloadsDirMode = rawMode ?? 'unset';
    if (downloadsDirMode != 'unset' &&
        downloadsDirMode != 'internal' &&
        downloadsDirMode != 'custom') {
      downloadsDirMode = 'unset';
    }
    // Migration: anciennes installations sans clé explicite -> interne (pas de prompt).
    if (rawMode == null) {
      downloadsDirMode = downloadsDir.isNotEmpty ? 'custom' : 'internal';
    }
    if (downloadsDirMode == 'custom' && downloadsDir.isEmpty) {
      downloadsDirMode = 'unset';
    }
    return AppSettings(
      themeMode: _pick(
        ThemeMode.values,
        _box.get('themeMode'),
        ThemeMode.system,
      ),
      seedIndex: (_box.get('seedIndex') as int?) ?? 0,
      readerMode: _pick(
        ReaderMode.values,
        _box.get('readerMode'),
        ReaderMode.webtoon,
      ),
      contentLanguage: (_box.get('language') as String?) ?? 'fr',
      dataSaver: (_box.get('dataSaver') as bool?) ?? true,
      libraryGrid: (_box.get('libraryGrid') as bool?) ?? true,
      pinnedSources: pinned is List
          ? pinned.map((e) => '$e').toList()
          : const [],
      localRoot: (_box.get('localRoot') as String?) ?? '',
      localCovers: _covers(_box.get('localCovers')),
      updatesIntervalHours: (_box.get('updatesIntervalHours') as int?) ?? 6,
      downloadsDir: downloadsDir,
      showNsfw: (_box.get('showNsfw') as bool?) ?? false,
      downloadsDirMode: downloadsDirMode,
      downloadsOnMobileData:
          (_box.get('downloadsOnMobileData') as bool?) ?? false,
      notificationsEnabled: (_box.get('notificationsEnabled') as bool?) ?? true,
      keepScreenOn: (_box.get('keepScreenOn') as bool?) ?? true,
      readerBrightness: (_box.get('readerBrightness') as num?)?.toDouble() ?? -1,
    );
  }

  /// Les cartes Hive reviennent en `Map<dynamic, dynamic>` : on normalise.
  Map<String, String> _covers(Object? value) {
    if (value is! Map) return const {};
    return {for (final e in value.entries) '${e.key}': '${e.value}'};
  }

  /// Enregistre tous les réglages (appelé à chaque changement).
  Future<void> save(AppSettings s) {
    return _box.putAll({
      'themeMode': s.themeMode.name,
      'seedIndex': s.seedIndex,
      'readerMode': s.readerMode.name,
      'language': s.contentLanguage,
      'dataSaver': s.dataSaver,
      'libraryGrid': s.libraryGrid,
      'pinned': s.pinnedSources,
      'localRoot': s.localRoot,
      'localCovers': s.localCovers,
      'updatesIntervalHours': s.updatesIntervalHours,
      'downloadsDir': s.downloadsDir,
      'showNsfw': s.showNsfw,
      'downloadsDirMode': s.downloadsDirMode,
      'downloadsOnMobileData': s.downloadsOnMobileData,
      'notificationsEnabled': s.notificationsEnabled,
      'keepScreenOn': s.keepScreenOn,
      'readerBrightness': s.readerBrightness,
    });
  }
}
