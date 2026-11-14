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
    this.dataSaver = false,
    this.libraryGrid = true,
    this.pinnedSources = const [],
  });

  final ThemeMode themeMode;
  final int seedIndex;
  final ReaderMode readerMode;
  final String contentLanguage;
  final bool dataSaver;
  final bool libraryGrid;
  final List<String> pinnedSources;

  AppSettings copyWith({
    ThemeMode? themeMode,
    int? seedIndex,
    ReaderMode? readerMode,
    String? contentLanguage,
    bool? dataSaver,
    bool? libraryGrid,
    List<String>? pinnedSources,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      seedIndex: seedIndex ?? this.seedIndex,
      readerMode: readerMode ?? this.readerMode,
      contentLanguage: contentLanguage ?? this.contentLanguage,
      dataSaver: dataSaver ?? this.dataSaver,
      libraryGrid: libraryGrid ?? this.libraryGrid,
      pinnedSources: pinnedSources ?? this.pinnedSources,
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
      dataSaver: (_box.get('dataSaver') as bool?) ?? false,
      libraryGrid: (_box.get('libraryGrid') as bool?) ?? true,
      pinnedSources: pinned is List
          ? pinned.map((e) => '$e').toList()
          : const [],
    );
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
    });
  }
}
