// creer_manga_reader.dart
//
// Génère automatiquement une application Flutter de lecture de manga / manhwa
// (type Mihon / Tachiyomi) : bibliothèque avec catégories, catalogue de sources
// (MangaDex + source locale), page de détails, lecteur (vertical, horizontal,
// double page, zoom), téléchargements hors ligne, historique et réglages.
//
// UTILISATION (dans un terminal, dans le dossier où tu veux créer le projet) :
//
//     dart creer_manga_reader.dart               ->  crée le dossier « manga_reader »
//     dart creer_manga_reader.dart mon_dossier   ->  crée le projet dans « mon_dossier »
//
// PRÉREQUIS : Flutter installé (la commande `dart` est fournie avec Flutter).
//
// Le script fait tout seul : flutter create -> écriture du code -> ajout des
// dépendances -> permission internet Android -> flutter pub get -> flutter analyze.

// ignore_for_file: avoid_print

import 'dart:io';

/// Nom du package Dart (utilisé dans pubspec.yaml). Ne pas changer.
const _packageName = 'manga_reader';

/// Identifiant de l'application Android : <org>.<package>
const _androidOrg = 'dev.mangareader';

/// Dépendances ajoutées dans pubspec.yaml (versions volontairement fixées).
const _dependencies = <String, String>{
  'flutter_riverpod': '^2.6.1',
  'dio': '^5.7.0',
  'hive': '^2.2.3',
  'hive_flutter': '^1.1.0',
  'cached_network_image': '^3.4.1',
  'flutter_cache_manager': '^3.4.1',
  'path_provider': '^2.1.4',
  'scrollable_positioned_list': '^0.3.8',
  'file_picker': '^8.1.7',
  'archive': '^4.0.2',
  'path': '^1.9.0',
};

const _totalSteps = 6;

Future<void> main(List<String> args) async {
  final folder = args.isNotEmpty ? args.first : _packageName;
  print('=== Générateur de « Manga Reader » ===');

  _step(1, 'Vérification de Flutter');
  if (!await _commandWorks('flutter', const ['--version'])) {
    _fail(
      'La commande « flutter » est introuvable.\n'
      '  Installe Flutter et ajoute-le au PATH : https://docs.flutter.dev/get-started/install',
    );
  }

  if (Directory(folder).existsSync() || File(folder).existsSync()) {
    _fail(
      '« $folder » existe déjà.\n'
      '  Choisis un autre nom :  dart creer_manga_reader.dart autre_nom',
    );
  }

  _step(2, 'Création du projet Flutter (patiente un peu…)');
  await _run('flutter', [
    'create',
    '--project-name',
    _packageName,
    '--org',
    _androidOrg,
    '--platforms',
    'android',
    folder,
  ]);

  _step(3, 'Écriture du code de l\'application (${_files.length} fichiers)');
  _writeFiles(folder);
  _deleteDefaultTest(folder);

  _step(4, 'Configuration (dépendances, permission internet)');
  _patchPubspec(folder);
  _patchManifest(folder);

  _step(5, 'Téléchargement des dépendances (flutter pub get)');
  await _run('flutter', ['pub', 'get'], workingDirectory: folder);

  _step(6, 'Analyse du code (flutter analyze)');
  final analyzeCode = await _run(
    'flutter',
    ['analyze', '--no-fatal-infos', '--no-fatal-warnings'],
    workingDirectory: folder,
    allowFailure: true,
  );

  print('');
  if (analyzeCode == 0) {
    print('✓ Projet créé, aucune erreur détectée.');
  } else {
    print('⚠ Projet créé, mais l\'analyse a signalé des erreurs (voir ci-dessus).');
    print('  Copie-colle ces messages pour qu\'on les corrige ensemble.');
  }
  print('');
  print('Pour lancer l\'application (téléphone branché ou émulateur Android) :');
  print('  cd $folder');
  print('  flutter run');
}

// ---------------------------------------------------------------------------
// Outils
// ---------------------------------------------------------------------------

void _step(int number, String text) => print('\n[$number/$_totalSteps] $text');

Never _fail(String message) {
  stderr.writeln('\n✗ $message');
  exit(1);
}

Future<bool> _commandWorks(String command, List<String> args) async {
  try {
    final result = await Process.run(command, args, runInShell: true);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// Lance une commande en affichant sa sortie. Renvoie son code de sortie.
Future<int> _run(
  String command,
  List<String> args, {
  String? workingDirectory,
  bool allowFailure = false,
}) async {
  final process = await Process.start(
    command,
    args,
    workingDirectory: workingDirectory,
    runInShell: true,
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await process.exitCode;
  if (code != 0 && !allowFailure) {
    _fail('La commande « $command ${args.join(' ')} » a échoué (code $code).');
  }
  return code;
}

void _writeFiles(String folder) {
  for (final entry in _files.entries) {
    final file = File('$folder/${entry.key}');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(entry.value);
  }
}

/// Le test généré par défaut référence l'ancienne classe MyApp : on le supprime.
void _deleteDefaultTest(String folder) {
  final test = File('$folder/test/widget_test.dart');
  if (test.existsSync()) test.deleteSync();
}

/// Ajoute les dépendances juste après « flutter: sdk: flutter ».
void _patchPubspec(String folder) {
  final file = File('$folder/pubspec.yaml');
  final text = file.readAsStringSync();
  final marker = RegExp(
    r'dependencies:[ \t]*\r?\n[ \t]+flutter:[ \t]*\r?\n[ \t]+sdk:[ \t]*flutter',
  );
  final match = marker.firstMatch(text);
  final lines = _dependencies.entries.map((e) => '  ${e.key}: ${e.value}');
  if (match == null) {
    print('⚠ Impossible de modifier pubspec.yaml automatiquement.');
    print('  Ajoute ces lignes sous « dependencies: » puis lance « flutter pub get » :');
    lines.forEach(print);
    return;
  }
  file.writeAsStringSync(
    text.replaceRange(match.end, match.end, '\n${lines.join('\n')}'),
  );
  print('  pubspec.yaml : ${_dependencies.length} dépendances ajoutées');
}

/// Autorise l'accès à internet (obligatoire pour les versions « release ») et nomme l'appli.
void _patchManifest(String folder) {
  final file = File('$folder/android/app/src/main/AndroidManifest.xml');
  if (!file.existsSync()) {
    print('⚠ AndroidManifest.xml introuvable : ajoute la permission INTERNET à la main.');
    return;
  }
  var text = file.readAsStringSync();
  if (!text.contains('android.permission.INTERNET')) {
    text = text.replaceFirstMapped(
      RegExp(r'<manifest[^>]*>'),
      (m) => '${m[0]}\n    <uses-permission android:name="android.permission.INTERNET"/>',
    );
  }
  text = text.replaceFirst('android:label="$_packageName"', 'android:label="Manga Reader"');
  file.writeAsStringSync(text);
  print('  AndroidManifest.xml : permission INTERNET ajoutée');
}

// ---------------------------------------------------------------------------
// Code source de l'application (chemin -> contenu). Généré automatiquement.
// ---------------------------------------------------------------------------

const _files = <String, String>{
  'README.md': r'''
# Manga Reader

Lecteur de manga / manhwa inspiré de Mihon et Tachiyomi, écrit en Flutter.
Projet généré automatiquement par `creer_manga_reader.dart`.

## Lancer l'application

```
flutter pub get
flutter run
```

## Organisation du code (`lib/`)

| Dossier | Rôle |
|---|---|
| `core/` | Constantes, thème, utilitaires et `providers.dart` (tous les providers Riverpod globaux) |
| `data/models/` | `Manga`, `Chapter`, `MangaPage`, `Category`, `LibraryEntry`, `MangaProgress`, `HistoryEntry` (avec JSON) |
| `data/storage/` + `data/repositories/` | Base de données locale Hive (bibliothèque, progression, historique, catégories, réglages) |
| `data/sources/` | Les sources : `MangaSource` (interface), `MangaDexSource`, `LocalMangaSource` |
| `data/downloads/` | Téléchargement des chapitres pour la lecture hors connexion |
| `features/` | Un dossier par écran : library, browse, details, reader, history, settings |
| `shared/widgets/` | Widgets réutilisés (carte de manga, couverture, états vides/erreur…) |

## Source locale

Dans Explorer, utilise l’icône de dossier. Chaque sous-dossier du répertoire choisi est un manga ; ses sous-dossiers ou fichiers `.cbz` sont des chapitres. Images prises en charge : JPG, PNG, WEBP et GIF.

## Ajouter une source

1. Crée `lib/data/sources/ma_source.dart` avec une classe qui `implements MangaSource`
   (regarde `mangadex_source.dart` comme exemple d'implémentation).
2. Ajoute-la dans la liste `sourcesProvider` de `lib/core/providers.dart`.

Elle apparaît alors dans l'onglet « Explorer ».

## Remarques

- La source MangaDex utilise l'API publique officielle (contenus « safe » et « suggestive »).
- Les téléchargements ne tournent que lorsque l'application est ouverte.
- Gestion d'état : Riverpod 2.x (volontairement figé sur `^2.6.1`).
''',
  'lib/app.dart': r'''
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants.dart';
import 'core/providers.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/format.dart';
import 'features/home/home_shell.dart';

class MangaReaderApp extends ConsumerWidget {
  const MangaReaderApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));
    final seedIndex = ref.watch(settingsProvider.select((s) => s.seedIndex));
    final seed = kSeedColors[clampInt(seedIndex, 0, kSeedColors.length - 1)];

    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(seed, Brightness.light),
      darkTheme: buildTheme(seed, Brightness.dark),
      themeMode: themeMode,
      home: const HomeShell(),
    );
  }
}
''',
  'lib/core/constants.dart': r'''
class AppConstants {
  static const appName = 'Manga Reader';
  static const version = '1.0.0';
  static const userAgent = 'MangaReaderFlutter/1.0 (projet personnel)';
}
''',
  'lib/core/providers.dart': r'''
import 'package:dio/dio.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/downloads/download_service.dart';
import '../data/models/category.dart';
import '../data/models/history_entry.dart';
import '../data/models/library_entry.dart';
import '../data/models/manga_progress.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/history_repository.dart';
import '../data/repositories/library_repository.dart';
import '../data/repositories/progress_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/sources/local_source.dart';
import '../data/sources/manga_source.dart';
import '../data/sources/mangadex_source.dart';
import '../data/storage/storage_service.dart';
import 'constants.dart';

// ------------------------------------------------------------------ stockage

/// Fourni dans main() une fois la base de données ouverte.
final storageProvider = Provider<StorageService>((ref) {
  throw UnimplementedError('storageProvider doit être fourni dans main()');
});

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  final s = ref.watch(storageProvider);
  return LibraryRepository(s.libraryBox, s.chapterIdsBox);
});

final progressRepositoryProvider = Provider<ProgressRepository>(
  (ref) => ProgressRepository(ref.watch(storageProvider).progressBox),
);

final historyRepositoryProvider = Provider<HistoryRepository>(
  (ref) => HistoryRepository(ref.watch(storageProvider).historyBox),
);

final categoryRepositoryProvider = Provider<CategoryRepository>(
  (ref) => CategoryRepository(ref.watch(storageProvider).categoriesBox),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(storageProvider).settingsBox),
);

// Flux réactifs : l'interface se met à jour toute seule quand la base change.

final libraryEntriesProvider = StreamProvider<List<LibraryEntry>>(
  (ref) => ref.watch(libraryRepositoryProvider).watch(),
);

/// Clés (source:id) des mangas présents dans la bibliothèque.
final libraryKeysProvider = Provider<Set<String>>((ref) {
  final entries =
      ref.watch(libraryEntriesProvider).value ?? const <LibraryEntry>[];
  return {for (final e in entries) e.manga.key};
});

final categoriesProvider = StreamProvider<List<Category>>(
  (ref) => ref.watch(categoryRepositoryProvider).watch(),
);

final allProgressProvider = StreamProvider<Map<String, MangaProgress>>(
  (ref) => ref.watch(progressRepositoryProvider).watchAll(),
);

final mangaProgressProvider = StreamProvider.autoDispose
    .family<MangaProgress, String>(
      (ref, mangaKey) =>
          ref.watch(progressRepositoryProvider).watchOne(mangaKey),
    );

final historyProvider = StreamProvider<List<HistoryEntry>>(
  (ref) => ref.watch(historyRepositoryProvider).watch(),
);

// ------------------------------------------------------------------- réglages

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(settingsRepositoryProvider).load();

  void _update(AppSettings next) {
    state = next;
    ref.read(settingsRepositoryProvider).save(next);
  }

  void setThemeMode(ThemeMode mode) => _update(state.copyWith(themeMode: mode));
  void setSeedIndex(int index) => _update(state.copyWith(seedIndex: index));
  void setReaderMode(ReaderMode mode) =>
      _update(state.copyWith(readerMode: mode));
  void setContentLanguage(String code) =>
      _update(state.copyWith(contentLanguage: code));
  void setDataSaver(bool value) => _update(state.copyWith(dataSaver: value));
  void setLibraryGrid(bool value) =>
      _update(state.copyWith(libraryGrid: value));

  void togglePinned(String sourceId) {
    final pinned = [...state.pinnedSources];
    if (!pinned.remove(sourceId)) pinned.add(sourceId);
    _update(state.copyWith(pinnedSources: pinned));
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

// -------------------------------------------------------------------- réseau

final dioProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'User-Agent': AppConstants.userAgent},
    ),
  );
});

final downloadServiceProvider = Provider<DownloadService>(
  (ref) => DownloadService(ref.watch(dioProvider)),
);

// ------------------------------------------------------------------- sources

final mangaDexSourceProvider = Provider<MangaSource>((ref) {
  return MangaDexSource(
    ref.watch(dioProvider),
    language: () => ref.read(settingsProvider).contentLanguage,
    dataSaver: () => ref.read(settingsProvider).dataSaver,
  );
});

final localSourceProvider = Provider<LocalMangaSource>((ref) => LocalMangaSource());

/// Les extensions externes doivent fournir un adaptateur compilé dans l'application.
final sourcesProvider = Provider<List<MangaSource>>((ref) {
  return [ref.watch(mangaDexSourceProvider), ref.watch(localSourceProvider)];
});

final sourceByIdProvider = Provider.family<MangaSource?, String>((ref, id) {
  for (final source in ref.watch(sourcesProvider)) {
    if (source.id == id) return source;
  }
  return null;
});
''',
  'lib/core/theme/app_theme.dart': r'''
import 'package:flutter/material.dart';

/// Couleurs principales proposées dans les paramètres.
const List<Color> kSeedColors = [
  Color(0xFF6750A4),
  Color(0xFF1565C0),
  Color(0xFF00897B),
  Color(0xFF2E7D32),
  Color(0xFFEF6C00),
  Color(0xFFD81B60),
  Color(0xFFC62828),
  Color(0xFF455A64),
];

/// Gris semi-transparent, lisible en thème clair comme en thème sombre.
const Color kPlaceholderColor = Color(0x33808080);

ThemeData buildTheme(Color seed, Brightness brightness) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: brightness),
  );
}
''',
  'lib/core/utils/errors.dart': r'''
import 'package:dio/dio.dart';

/// Transforme une erreur technique en message compréhensible.
String describeError(Object error) {
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Le serveur met trop de temps à répondre.';
      case DioExceptionType.connectionError:
        return 'Pas de connexion internet.';
      case DioExceptionType.badResponse:
        final code = error.response?.statusCode;
        if (code == 429) return 'Trop de requêtes, réessaie dans un instant.';
        return 'Erreur du serveur (code ${code ?? '?'}).';
      default:
        return 'Impossible de contacter le serveur.';
    }
  }
  return error.toString().replaceFirst('Exception: ', '');
}
''',
  'lib/core/utils/files.dart': r'''
import 'dart:io';

/// Taille totale (en octets) des fichiers d'un dossier.
Future<int> directorySize(Directory dir) async {
  if (!await dir.exists()) return 0;
  var total = 0;
  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is File) {
      try {
        total += await entity.length();
      } catch (_) {
        // fichier supprimé entre-temps : on ignore
      }
    }
  }
  return total;
}
''',
  'lib/core/utils/format.dart': r'''
int clampInt(int value, int min, int max) =>
    value < min ? min : (value > max ? max : value);

String formatDate(DateTime? d) {
  if (d == null) return '';
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '$dd/$mm/${d.year}';
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes o';
  const units = ['Ko', 'Mo', 'Go', 'To'];
  var value = bytes / 1024;
  var i = 0;
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024;
    i++;
  }
  return '${value.toStringAsFixed(value < 10 ? 1 : 0)} ${units[i]}';
}

String formatRelative(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return "À l'instant";
  if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'Il y a ${diff.inHours} h';
  if (diff.inDays < 7) return 'Il y a ${diff.inDays} j';
  return formatDate(d);
}
''',
  'lib/data/downloads/download_service.dart': r'''
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/utils/files.dart';
import '../models/chapter.dart';
import '../models/manga.dart';
import '../sources/manga_source.dart';

/// Télécharge les pages d'un chapitre dans le stockage de l'application
/// pour pouvoir le lire hors connexion.
class DownloadService {
  DownloadService(this._dio);

  final Dio _dio;
  Directory? _root;

  Future<Directory> _rootDir() async {
    final cached = _root;
    if (cached != null) return cached;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/downloads');
    await dir.create(recursive: true);
    _root = dir;
    return dir;
  }

  String _safe(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');

  /// Nom du dossier d'un chapitre téléchargé.
  String folderOf(Chapter chapter) => _safe(chapter.id);

  Future<Directory> _mangaDir(Manga manga) async {
    final root = await _rootDir();
    return Directory(
      '${root.path}/${_safe(manga.sourceId)}/${_safe(manga.id)}',
    );
  }

  Future<Directory> _chapterDir(Manga manga, Chapter chapter) async {
    final dir = await _mangaDir(manga);
    return Directory('${dir.path}/${folderOf(chapter)}');
  }

  /// Dossiers des chapitres entièrement téléchargés pour ce manga.
  Future<Set<String>> downloadedFolders(Manga manga) async {
    final dir = await _mangaDir(manga);
    final result = <String>{};
    if (!await dir.exists()) return result;
    await for (final entity in dir.list()) {
      if (entity is Directory &&
          await File('${entity.path}/.complete').exists()) {
        result.add(entity.path.split(RegExp(r'[\\/]')).last);
      }
    }
    return result;
  }

  /// Chemins des pages si le chapitre est entièrement téléchargé, sinon null.
  Future<List<String>?> localPages(Manga manga, Chapter chapter) async {
    final dir = await _chapterDir(manga, chapter);
    final marker = File('${dir.path}/.complete');
    if (!await marker.exists()) return null;
    final count = int.tryParse(await marker.readAsString()) ?? 0;
    if (count <= 0) return null;
    return [for (var i = 0; i < count; i++) '${dir.path}/$i.img'];
  }

  Future<void> downloadChapter({
    required MangaSource source,
    required Manga manga,
    required Chapter chapter,
    void Function(double progress)? onProgress,
  }) async {
    final pages = await source.fetchPages(chapter);
    if (pages.isEmpty) throw StateError('Aucune page à télécharger.');
    final dir = await _chapterDir(manga, chapter);
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    try {
      for (var i = 0; i < pages.length; i++) {
        await _dio.download(pages[i].imageUrl, '${dir.path}/$i.img');
        onProgress?.call((i + 1) / pages.length);
      }
      // Ce fichier prouve que tout est téléchargé (et contient le nombre de pages).
      await File('${dir.path}/.complete').writeAsString('${pages.length}');
    } catch (_) {
      if (await dir.exists()) await dir.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> deleteChapter(Manga manga, Chapter chapter) async {
    final dir = await _chapterDir(manga, chapter);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future<int> totalSize() async => directorySize(await _rootDir());

  Future<void> clearAll() async {
    final root = await _rootDir();
    if (await root.exists()) await root.delete(recursive: true);
    await root.create(recursive: true);
  }
}
''',
  'lib/data/models/category.dart': r'''
class Category {
  const Category({required this.id, required this.name, this.order = 0});

  final String id;
  final String name;
  final int order;

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] as String,
      name: json['name'] as String,
      order: (json['order'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'order': order};
}
''',
  'lib/data/models/chapter.dart': r'''
class Chapter {
  const Chapter({
    required this.id,
    required this.mangaId,
    required this.sourceId,
    this.number,
    this.title = '',
    this.volume,
    this.publishedAt,
    this.pageCount = 0,
    this.scanlator,
  });

  final String id;
  final String mangaId;
  final String sourceId;
  final String? number;
  final String title;
  final String? volume;
  final DateTime? publishedAt;
  final int pageCount;
  final String? scanlator;

  double get numberValue => double.tryParse(number ?? '') ?? -1;

  String get displayTitle {
    final n = number;
    if (n == null) return title.isEmpty ? 'One-shot' : title;
    return title.isEmpty ? 'Chapitre $n' : 'Chapitre $n – $title';
  }

  factory Chapter.fromJson(Map<String, dynamic> json) {
    return Chapter(
      id: json['id'] as String,
      mangaId: json['mangaId'] as String,
      sourceId: json['sourceId'] as String,
      number: json['number'] as String?,
      title: (json['title'] as String?) ?? '',
      volume: json['volume'] as String?,
      publishedAt: DateTime.tryParse((json['publishedAt'] as String?) ?? ''),
      pageCount: (json['pageCount'] as num?)?.toInt() ?? 0,
      scanlator: json['scanlator'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'mangaId': mangaId,
    'sourceId': sourceId,
    'number': number,
    'title': title,
    'volume': volume,
    'publishedAt': publishedAt?.toIso8601String(),
    'pageCount': pageCount,
    'scanlator': scanlator,
  };
}
''',
  'lib/data/models/history_entry.dart': r'''
import 'manga.dart';

/// Dernier chapitre lu pour un manga (une ligne par manga dans l'historique).
class HistoryEntry {
  const HistoryEntry({
    required this.manga,
    required this.chapterId,
    required this.chapterTitle,
    required this.page,
    required this.readAt,
  });

  final Manga manga;
  final String chapterId;
  final String chapterTitle;
  final int page;
  final DateTime readAt;

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    return HistoryEntry(
      manga: Manga.fromJson((json['manga'] as Map).cast<String, dynamic>()),
      chapterId: json['chapterId'] as String,
      chapterTitle: (json['chapterTitle'] as String?) ?? '',
      page: (json['page'] as num?)?.toInt() ?? 0,
      readAt:
          DateTime.tryParse((json['readAt'] as String?) ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'manga': manga.toJson(),
    'chapterId': chapterId,
    'chapterTitle': chapterTitle,
    'page': page,
    'readAt': readAt.toIso8601String(),
  };
}
''',
  'lib/data/models/library_entry.dart': r'''
import 'manga.dart';

/// Un manga enregistré dans la bibliothèque.
class LibraryEntry {
  const LibraryEntry({
    required this.manga,
    required this.addedAt,
    this.categoryIds = const [],
    this.chapterCount = 0,
  });

  final Manga manga;
  final DateTime addedAt;
  final List<String> categoryIds;
  final int chapterCount;

  LibraryEntry copyWith({
    Manga? manga,
    List<String>? categoryIds,
    int? chapterCount,
  }) {
    return LibraryEntry(
      manga: manga ?? this.manga,
      addedAt: addedAt,
      categoryIds: categoryIds ?? this.categoryIds,
      chapterCount: chapterCount ?? this.chapterCount,
    );
  }

  factory LibraryEntry.fromJson(Map<String, dynamic> json) {
    return LibraryEntry(
      manga: Manga.fromJson((json['manga'] as Map).cast<String, dynamic>()),
      addedAt:
          DateTime.tryParse((json['addedAt'] as String?) ?? '') ??
          DateTime.now(),
      categoryIds: ((json['categories'] as List?) ?? const [])
          .map((e) => '$e')
          .toList(),
      chapterCount: (json['chapterCount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'manga': manga.toJson(),
    'addedAt': addedAt.toIso8601String(),
    'categories': categoryIds,
    'chapterCount': chapterCount,
  };
}
''',
  'lib/data/models/manga.dart': r'''
enum MangaStatus { ongoing, completed, hiatus, cancelled, unknown }

extension MangaStatusX on MangaStatus {
  String get label => switch (this) {
    MangaStatus.ongoing => 'En cours',
    MangaStatus.completed => 'Terminé',
    MangaStatus.hiatus => 'En pause',
    MangaStatus.cancelled => 'Abandonné',
    MangaStatus.unknown => 'Statut inconnu',
  };
}

class Manga {
  const Manga({
    required this.id,
    required this.sourceId,
    required this.title,
    this.coverUrl,
    this.author,
    this.artist,
    this.description = '',
    this.status = MangaStatus.unknown,
    this.genres = const [],
  });

  final String id;
  final String sourceId;
  final String title;
  final String? coverUrl;
  final String? author;
  final String? artist;
  final String description;
  final MangaStatus status;
  final List<String> genres;

  /// Clé unique dans toute l'application (source + id).
  String get key => '$sourceId:$id';

  factory Manga.fromJson(Map<String, dynamic> json) {
    return Manga(
      id: json['id'] as String,
      sourceId: json['sourceId'] as String,
      title: json['title'] as String,
      coverUrl: json['coverUrl'] as String?,
      author: json['author'] as String?,
      artist: json['artist'] as String?,
      description: (json['description'] as String?) ?? '',
      status: MangaStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => MangaStatus.unknown,
      ),
      genres: ((json['genres'] as List?) ?? const []).map((e) => '$e').toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'sourceId': sourceId,
    'title': title,
    'coverUrl': coverUrl,
    'author': author,
    'artist': artist,
    'description': description,
    'status': status.name,
    'genres': genres,
  };

  @override
  bool operator ==(Object other) => other is Manga && other.key == key;

  @override
  int get hashCode => key.hashCode;
}
''',
  'lib/data/models/manga_page.dart': r'''
/// Une page d'un chapitre. (Nommée MangaPage car `Page` existe déjà dans Flutter.)
class MangaPage {
  const MangaPage({
    required this.index,
    required this.imageUrl,
    this.cacheKey,
    this.localPath,
  });

  final int index;
  final String imageUrl;

  /// Clé de cache stable (l'URL du serveur peut changer d'une session à l'autre).
  final String? cacheKey;

  /// Chemin du fichier si le chapitre est téléchargé.
  final String? localPath;

  factory MangaPage.fromJson(Map<String, dynamic> json) {
    return MangaPage(
      index: (json['index'] as num).toInt(),
      imageUrl: json['imageUrl'] as String,
      cacheKey: json['cacheKey'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'index': index,
    'imageUrl': imageUrl,
    'cacheKey': cacheKey,
  };
}
''',
  'lib/data/models/manga_progress.dart': r'''
/// Progression de lecture d'un manga : chapitres lus + dernière page de chaque chapitre.
class MangaProgress {
  const MangaProgress({
    this.readChapterIds = const {},
    this.lastPage = const {},
  });

  final Set<String> readChapterIds;
  final Map<String, int> lastPage;

  bool isRead(String chapterId) => readChapterIds.contains(chapterId);
  int pageOf(String chapterId) => lastPage[chapterId] ?? 0;
  bool get isEmpty => readChapterIds.isEmpty && lastPage.isEmpty;

  factory MangaProgress.fromJson(Map<String, dynamic> json) {
    final pages = (json['pages'] as Map?) ?? const {};
    return MangaProgress(
      readChapterIds: ((json['read'] as List?) ?? const [])
          .map((e) => '$e')
          .toSet(),
      lastPage: {
        for (final e in pages.entries) '${e.key}': (e.value as num).toInt(),
      },
    );
  }

  Map<String, dynamic> toJson() => {
    'read': readChapterIds.toList(),
    'pages': lastPage,
  };
}
''',
  'lib/data/repositories/category_repository.dart': r'''
import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/category.dart';

class CategoryRepository {
  CategoryRepository(this._box);

  final Box<String> _box;

  List<Category> all() {
    final result = <Category>[];
    for (final raw in _box.values) {
      try {
        result.add(Category.fromJson(jsonDecode(raw) as Map<String, dynamic>));
      } catch (_) {
        // entrée illisible : on l'ignore
      }
    }
    result.sort((a, b) => a.order.compareTo(b.order));
    return result;
  }

  Stream<List<Category>> watch() async* {
    yield all();
    await for (final _ in _box.watch()) {
      yield all();
    }
  }

  Future<void> add(String name) {
    final existing = all();
    final category = Category(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.trim(),
      order: existing.isEmpty ? 0 : existing.last.order + 1,
    );
    return _box.put(category.id, jsonEncode(category.toJson()));
  }

  Future<void> delete(String id) => _box.delete(id);
}
''',
  'lib/data/repositories/history_repository.dart': r'''
import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/chapter.dart';
import '../models/history_entry.dart';
import '../models/manga.dart';

class HistoryRepository {
  HistoryRepository(this._box);

  final Box<String> _box;

  List<HistoryEntry> all() {
    final result = <HistoryEntry>[];
    for (final raw in _box.values) {
      try {
        result.add(
          HistoryEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>),
        );
      } catch (_) {
        // entrée illisible : on l'ignore
      }
    }
    result.sort((a, b) => b.readAt.compareTo(a.readAt));
    return result;
  }

  Stream<List<HistoryEntry>> watch() async* {
    yield all();
    await for (final _ in _box.watch()) {
      yield all();
    }
  }

  Future<void> record(Manga manga, Chapter chapter, int page) {
    final entry = HistoryEntry(
      manga: manga,
      chapterId: chapter.id,
      chapterTitle: chapter.displayTitle,
      page: page,
      readAt: DateTime.now(),
    );
    return _box.put(manga.key, jsonEncode(entry.toJson()));
  }

  Future<void> remove(String mangaKey) => _box.delete(mangaKey);

  Future<void> clear() async {
    await _box.clear();
  }
}
''',
  'lib/data/repositories/library_repository.dart': r'''
import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/library_entry.dart';
import '../models/manga.dart';

class LibraryRepository {
  LibraryRepository(this._entries, this._chapterIds);

  final Box<String> _entries;
  final Box<String> _chapterIds;

  List<LibraryEntry> all() {
    final result = <LibraryEntry>[];
    for (final raw in _entries.values) {
      try {
        result.add(
          LibraryEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>),
        );
      } catch (_) {
        // entrée illisible : on l'ignore
      }
    }
    result.sort(
      (a, b) =>
          a.manga.title.toLowerCase().compareTo(b.manga.title.toLowerCase()),
    );
    return result;
  }

  /// Émet la liste complète à chaque modification de la base (stockage réactif).
  Stream<List<LibraryEntry>> watch() async* {
    yield all();
    await for (final _ in _entries.watch()) {
      yield all();
    }
  }

  bool contains(String key) => _entries.containsKey(key);

  LibraryEntry? get(String key) {
    final raw = _entries.get(key);
    if (raw == null) return null;
    try {
      return LibraryEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> add(Manga manga, {List<String> chapterIds = const []}) async {
    final existing = get(manga.key);
    final entry = LibraryEntry(
      manga: manga,
      addedAt: existing?.addedAt ?? DateTime.now(),
      categoryIds: existing?.categoryIds ?? const [],
      chapterCount: chapterIds.length,
    );
    await _put(entry);
    await _chapterIds.put(manga.key, jsonEncode(chapterIds));
  }

  Future<void> remove(String key) async {
    await _entries.delete(key);
    await _chapterIds.delete(key);
  }

  Future<void> setCategories(String key, List<String> categoryIds) async {
    final entry = get(key);
    if (entry == null) return;
    await _put(entry.copyWith(categoryIds: categoryIds));
  }

  /// Ids des chapitres connus d'un manga de la bibliothèque.
  List<String> chapterIds(String key) {
    final raw = _chapterIds.get(key);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List).map((e) => '$e').toList();
    } catch (_) {
      return const [];
    }
  }

  /// Met à jour la liste des chapitres (sert à calculer les badges "non lus").
  Future<void> saveChapterIds(String key, List<String> ids) async {
    final entry = get(key);
    if (entry == null) return;
    await _chapterIds.put(key, jsonEncode(ids));
    await _put(entry.copyWith(chapterCount: ids.length));
  }

  /// Si le manga est déjà en bibliothèque, rafraîchit ses infos et ses chapitres.
  Future<void> syncIfInLibrary(Manga manga, List<String> ids) async {
    final entry = get(manga.key);
    if (entry == null) return;
    await _chapterIds.put(manga.key, jsonEncode(ids));
    await _put(entry.copyWith(manga: manga, chapterCount: ids.length));
  }

  Future<void> _put(LibraryEntry entry) =>
      _entries.put(entry.manga.key, jsonEncode(entry.toJson()));
}
''',
  'lib/data/repositories/progress_repository.dart': r'''
import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/manga_progress.dart';

class ProgressRepository {
  ProgressRepository(this._box);

  final Box<String> _box;

  MangaProgress get(String mangaKey) {
    final raw = _box.get(mangaKey);
    if (raw == null) return const MangaProgress();
    try {
      return MangaProgress.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const MangaProgress();
    }
  }

  Stream<MangaProgress> watchOne(String mangaKey) async* {
    yield get(mangaKey);
    await for (final _ in _box.watch(key: mangaKey)) {
      yield get(mangaKey);
    }
  }

  Map<String, MangaProgress> _all() => {
    for (final k in _box.keys) '$k': get('$k'),
  };

  Stream<Map<String, MangaProgress>> watchAll() async* {
    yield _all();
    await for (final _ in _box.watch()) {
      yield _all();
    }
  }

  /// Enregistre la position dans un chapitre. Si [read] est vrai, le chapitre est marqué comme lu.
  Future<void> savePosition({
    required String mangaKey,
    required String chapterId,
    required int page,
    required bool read,
  }) async {
    final current = get(mangaKey);
    final readIds = {...current.readChapterIds};
    final pages = {...current.lastPage};
    if (read) {
      readIds.add(chapterId);
      pages.remove(chapterId);
    } else {
      pages[chapterId] = page;
    }
    await _put(
      mangaKey,
      MangaProgress(readChapterIds: readIds, lastPage: pages),
    );
  }

  /// Marque une liste de chapitres comme lus (ou non lus).
  Future<void> setRead(
    String mangaKey,
    Iterable<String> chapterIds,
    bool read,
  ) async {
    final current = get(mangaKey);
    final readIds = {...current.readChapterIds};
    final pages = {...current.lastPage};
    for (final id in chapterIds) {
      if (read) {
        readIds.add(id);
      } else {
        readIds.remove(id);
      }
      pages.remove(id);
    }
    await _put(
      mangaKey,
      MangaProgress(readChapterIds: readIds, lastPage: pages),
    );
  }

  Future<void> _put(String mangaKey, MangaProgress progress) =>
      _box.put(mangaKey, jsonEncode(progress.toJson()));
}
''',
  'lib/data/repositories/settings_repository.dart': r'''
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
''',
  'lib/data/sources/manga_source.dart': r'''
import '../models/chapter.dart';
import '../models/manga.dart';
import '../models/manga_page.dart';

enum CatalogSort { popularity, latest, title }

extension CatalogSortX on CatalogSort {
  String get label => switch (this) {
    CatalogSort.popularity => 'Popularité',
    CatalogSort.latest => 'Dernières mises à jour',
    CatalogSort.title => 'Nom (A-Z)',
  };
}

class Genre {
  const Genre({required this.id, required this.name});

  final String id;
  final String name;
}

/// Recherche + filtres + tri appliqués au catalogue d'une source.
class CatalogQuery {
  const CatalogQuery({
    this.text = '',
    this.sort = CatalogSort.popularity,
    this.genreIds = const {},
  });

  final String text;
  final CatalogSort sort;
  final Set<String> genreIds;

  bool get hasFilters => genreIds.isNotEmpty || sort != CatalogSort.popularity;

  CatalogQuery copyWith({
    String? text,
    CatalogSort? sort,
    Set<String>? genreIds,
  }) {
    return CatalogQuery(
      text: text ?? this.text,
      sort: sort ?? this.sort,
      genreIds: genreIds ?? this.genreIds,
    );
  }
}

class MangaPageResult {
  const MangaPageResult(this.mangas, this.hasNextPage);

  final List<Manga> mangas;
  final bool hasNextPage;
}

/// Une "source" = un site ou une API d'où viennent les mangas.
/// Pour en ajouter une : crée une classe qui implémente [MangaSource],
/// puis ajoute-la dans `sourcesProvider` (lib/core/providers.dart).
abstract class MangaSource {
  String get id;
  String get name;
  String get description;

  Future<MangaPageResult> fetchCatalog({
    required int page,
    required CatalogQuery query,
  });

  Future<Manga> fetchMangaDetails(Manga manga);

  /// Chapitres triés du plus ancien au plus récent.
  Future<List<Chapter>> fetchChapters(Manga manga);

  Future<List<MangaPage>> fetchPages(Chapter chapter);

  Future<List<Genre>> fetchGenres();
}
''',
  'lib/data/sources/local_source.dart': r'''
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/chapter.dart';
import '../models/manga.dart';
import '../models/manga_page.dart';
import 'manga_source.dart';

/// Chaque dossier enfant = manga ; sous-dossier ou CBZ = chapitre.
class LocalMangaSource implements MangaSource {
  String? _root;
  void setRoot(String path) => _root = path;
  @override String get id => 'local';
  @override String get name => 'Bibliothèque locale';
  @override String get description => _root ?? 'Aucun dossier importé';
  static bool _image(String path) => const ['.jpg','.jpeg','.png','.webp','.gif'].contains(p.extension(path).toLowerCase());
  List<File> _images(Directory dir) { if (!dir.existsSync()) return []; final files=dir.listSync().whereType<File>().where((f)=>_image(f.path)).toList(); files.sort((a,b)=>a.path.toLowerCase().compareTo(b.path.toLowerCase())); return files; }
  @override Future<MangaPageResult> fetchCatalog({required int page, required CatalogQuery query}) async {
    final root=_root; if(root==null || !Directory(root).existsSync()) return const MangaPageResult([],false);
    final dirs=Directory(root).listSync().whereType<Directory>().where((d)=>p.basename(d.path).toLowerCase().contains(query.text.toLowerCase())).toList()..sort((a,b)=>a.path.compareTo(b.path));
    final all=dirs.map((d)=>Manga(id:d.path,sourceId:id,title:p.basename(d.path))).toList(); final start=(page-1)*20; if(start>=all.length)return const MangaPageResult([],false); final end=(start+20).clamp(0,all.length); return MangaPageResult(all.sublist(start,end),end<all.length);
  }
  @override Future<Manga> fetchMangaDetails(Manga manga) async => manga;
  @override Future<List<Chapter>> fetchChapters(Manga manga) async {
    final dir=Directory(manga.id); if(!dir.existsSync())return [];
    final entries=dir.listSync().where((e)=>e is Directory || (e is File && p.extension(e.path).toLowerCase()=='.cbz')).toList()..sort((a,b)=>a.path.compareTo(b.path));
    return [for(var i=0;i<entries.length;i++) Chapter(id:entries[i].path,mangaId:manga.id,sourceId:id,number:'${i+1}',title:p.basenameWithoutExtension(entries[i].path),pageCount:entries[i] is Directory ? _images(Directory(entries[i].path)).length : 0)];
  }
  Future<Directory> _unzip(String filePath) async {
    final temp=await getTemporaryDirectory(); final out=Directory(p.join(temp.path,'manga_reader_cbz',p.basenameWithoutExtension(filePath)));
    if(!out.existsSync()) { final archive=ZipDecoder().decodeBytes(await File(filePath).readAsBytes()); for(final f in archive.files) { if(f.isFile && _image(f.name)) { final target=File(p.join(out.path,p.basename(f.name))); await target.parent.create(recursive:true); await target.writeAsBytes(f.content as List<int>); } } }
    return out;
  }
  @override Future<List<MangaPage>> fetchPages(Chapter chapter) async {
    final dir=chapter.id.toLowerCase().endsWith('.cbz') ? await _unzip(chapter.id) : Directory(chapter.id); final files=_images(dir);
    return [for(var i=0;i<files.length;i++) MangaPage(index:i,imageUrl:'',localPath:files[i].path,cacheKey:files[i].path)];
  }
  @override Future<List<Genre>> fetchGenres() async => const [];
}
''',
  'lib/data/sources/mangadex_source.dart': r'''
import 'package:dio/dio.dart';

import '../models/chapter.dart';
import '../models/manga.dart';
import '../models/manga_page.dart';
import 'manga_source.dart';

/// Source basée sur l'API publique de MangaDex (https://api.mangadex.org).
class MangaDexSource implements MangaSource {
  MangaDexSource(
    this._dio, {
    required this._language,
    required this._dataSaver,
  });

  final Dio _dio;
  final String Function() _language;
  final bool Function() _dataSaver;

  static const _host = 'api.mangadex.org';
  static const _pageSize = 20;
  static const _ratings = ['safe', 'suggestive'];

  List<Genre>? _genres;

  @override
  String get id => 'mangadex';

  @override
  String get name => 'MangaDex';

  @override
  String get description =>
      "Catalogue communautaire via l'API publique de MangaDex";

  // ---------------------------------------------------------------- catalogue

  @override
  Future<MangaPageResult> fetchCatalog({
    required int page,
    required CatalogQuery query,
  }) async {
    final offset = (page - 1) * _pageSize;
    final text = query.text.trim();
    final params = <String, dynamic>{
      'limit': '$_pageSize',
      'offset': '$offset',
      'includes[]': ['cover_art', 'author', 'artist'],
      'contentRating[]': _ratings,
      'availableTranslatedLanguage[]': [_language()],
      'hasAvailableChapters': 'true',
    };
    if (text.isNotEmpty) params['title'] = text;
    if (query.genreIds.isNotEmpty) {
      params['includedTags[]'] = query.genreIds.toList();
    }
    switch (query.sort) {
      case CatalogSort.popularity:
        // Avec un texte de recherche, on laisse MangaDex trier par pertinence.
        if (text.isEmpty) params['order[followedCount]'] = 'desc';
      case CatalogSort.latest:
        params['order[latestUploadedChapter]'] = 'desc';
      case CatalogSort.title:
        params['order[title]'] = 'asc';
    }

    final res = await _dio.getUri<Map<String, dynamic>>(
      Uri.https(_host, '/manga', params),
    );
    final body = res.data ?? const <String, dynamic>{};
    final items = ((body['data'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => _parseManga(m.cast<String, dynamic>()))
        .toList();
    final total = (body['total'] as num?)?.toInt() ?? 0;
    return MangaPageResult(items, offset + items.length < total);
  }

  @override
  Future<Manga> fetchMangaDetails(Manga manga) async {
    final uri = Uri.https(_host, '/manga/${manga.id}', {
      'includes[]': ['cover_art', 'author', 'artist'],
    });
    final res = await _dio.getUri<Map<String, dynamic>>(uri);
    final data = res.data?['data'];
    if (data is! Map) return manga;
    return _parseManga(data.cast<String, dynamic>(), coverSize: 512);
  }

  @override
  Future<List<Chapter>> fetchChapters(Manga manga) async {
    const limit = 500;
    final all = <Chapter>[];
    var offset = 0;
    while (true) {
      final uri = Uri.https(_host, '/manga/${manga.id}/feed', {
        'limit': '$limit',
        'offset': '$offset',
        'translatedLanguage[]': [_language()],
        'includes[]': ['scanlation_group'],
        'includeExternalUrl': '0',
        'order[chapter]': 'asc',
      });
      final res = await _dio.getUri<Map<String, dynamic>>(uri);
      final body = res.data ?? const <String, dynamic>{};
      final list = ((body['data'] as List?) ?? const []).whereType<Map>();
      for (final c in list) {
        all.add(_parseChapter(c.cast<String, dynamic>(), manga));
      }
      final total = (body['total'] as num?)?.toInt() ?? 0;
      offset += limit;
      if (offset >= total || list.isEmpty) break;
    }

    // Plusieurs groupes peuvent avoir traduit le même chapitre : on n'en garde qu'un.
    final byNumber = <String, Chapter>{};
    for (final c in all) {
      if (c.pageCount <= 0) continue;
      byNumber.putIfAbsent(c.number ?? c.id, () => c);
    }
    final result = byNumber.values.toList()
      ..sort((a, b) => a.numberValue.compareTo(b.numberValue));
    return result;
  }

  @override
  Future<List<MangaPage>> fetchPages(Chapter chapter) async {
    final res = await _dio.getUri<Map<String, dynamic>>(
      Uri.https(_host, '/at-home/server/${chapter.id}'),
    );
    final body = res.data ?? const <String, dynamic>{};
    final baseUrl = body['baseUrl'] as String;
    final info = (body['chapter'] as Map).cast<String, dynamic>();
    final hash = info['hash'] as String;
    final saver = _dataSaver();
    final files = ((saver ? info['dataSaver'] : info['data']) as List)
        .map((e) => '$e')
        .toList();
    final folder = saver ? 'data-saver' : 'data';
    return [
      for (var i = 0; i < files.length; i++)
        MangaPage(
          index: i,
          imageUrl: '$baseUrl/$folder/$hash/${files[i]}',
          cacheKey: '$folder/$hash/${files[i]}',
        ),
    ];
  }

  @override
  Future<List<Genre>> fetchGenres() async {
    final cached = _genres;
    if (cached != null) return cached;
    final res = await _dio.getUri<Map<String, dynamic>>(
      Uri.https(_host, '/manga/tag'),
    );
    final body = res.data ?? const <String, dynamic>{};
    final genres = <Genre>[];
    for (final tag in ((body['data'] as List?) ?? const []).whereType<Map>()) {
      final attrs = tag['attributes'];
      if (attrs is! Map) continue;
      final group = attrs['group'];
      if (group != 'genre' && group != 'theme') continue;
      final label = _localized(attrs['name']);
      if (label.isNotEmpty) genres.add(Genre(id: '${tag['id']}', name: label));
    }
    genres.sort((a, b) => a.name.compareTo(b.name));
    _genres = genres;
    return genres;
  }

  // ------------------------------------------------------------------ parsing

  /// Les textes MangaDex sont de la forme {"en": "...", "fr": "..."}.
  String _localized(Object? value, {String? prefer}) {
    if (value is! Map || value.isEmpty) return '';
    if (prefer != null) {
      final preferred = value[prefer];
      if (preferred is String && preferred.isNotEmpty) return preferred;
    }
    final english = value['en'];
    if (english is String && english.isNotEmpty) return english;
    for (final v in value.values) {
      if (v is String && v.isNotEmpty) return v;
    }
    return '';
  }

  MangaStatus _status(Object? value) => switch (value) {
    'ongoing' => MangaStatus.ongoing,
    'completed' => MangaStatus.completed,
    'hiatus' => MangaStatus.hiatus,
    'cancelled' => MangaStatus.cancelled,
    _ => MangaStatus.unknown,
  };

  Manga _parseManga(Map<String, dynamic> json, {int coverSize = 256}) {
    final mangaId = json['id'] as String;
    final attrs =
        (json['attributes'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final rels = ((json['relationships'] as List?) ?? const [])
        .whereType<Map>()
        .toList();

    String? relation(String type, String field) {
      for (final r in rels) {
        if (r['type'] != type) continue;
        final a = r['attributes'];
        if (a is Map && a[field] is String) return a[field] as String;
      }
      return null;
    }

    final fileName = relation('cover_art', 'fileName');

    final tags = <String>[];
    for (final t in ((attrs['tags'] as List?) ?? const []).whereType<Map>()) {
      final label = _localized((t['attributes'] as Map?)?['name']);
      if (label.isNotEmpty) tags.add(label);
    }

    var title = _localized(attrs['title']);
    if (title.isEmpty) {
      for (final alt in (attrs['altTitles'] as List?) ?? const []) {
        title = _localized(alt);
        if (title.isNotEmpty) break;
      }
    }
    if (title.isEmpty) title = 'Sans titre';

    return Manga(
      id: mangaId,
      sourceId: id,
      title: title,
      coverUrl: fileName == null
          ? null
          : 'https://uploads.mangadex.org/covers/$mangaId/$fileName.$coverSize.jpg',
      author: relation('author', 'name'),
      artist: relation('artist', 'name'),
      description: _localized(attrs['description'], prefer: _language()),
      status: _status(attrs['status']),
      genres: tags,
    );
  }

  Chapter _parseChapter(Map<String, dynamic> json, Manga manga) {
    final attrs =
        (json['attributes'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    String? group;
    for (final r
        in ((json['relationships'] as List?) ?? const []).whereType<Map>()) {
      if (r['type'] != 'scanlation_group') continue;
      final a = r['attributes'];
      if (a is Map && a['name'] is String) group = a['name'] as String;
    }
    final published =
        (attrs['readableAt'] ?? attrs['publishAt'] ?? '') as String;
    return Chapter(
      id: json['id'] as String,
      mangaId: manga.id,
      sourceId: id,
      number: attrs['chapter'] as String?,
      title: (attrs['title'] as String?) ?? '',
      volume: attrs['volume'] as String?,
      publishedAt: DateTime.tryParse(published),
      pageCount: (attrs['pages'] as num?)?.toInt() ?? 0,
      scanlator: group,
    );
  }
}
''',
  'lib/data/storage/storage_service.dart': r'''
import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/category.dart';

/// Ouvre les "boîtes" Hive (base de données locale clé → valeur).
/// Les objets sont stockés en JSON (texte), donc aucune génération de code n'est nécessaire.
class StorageService {
  StorageService._({
    required this.libraryBox,
    required this.chapterIdsBox,
    required this.progressBox,
    required this.historyBox,
    required this.categoriesBox,
    required this.settingsBox,
  });

  final Box<String> libraryBox;
  final Box<String> chapterIdsBox;
  final Box<String> progressBox;
  final Box<String> historyBox;
  final Box<String> categoriesBox;
  final Box<dynamic> settingsBox;

  static Future<StorageService> init() async {
    await Hive.initFlutter();
    final service = StorageService._(
      libraryBox: await Hive.openBox<String>('library'),
      chapterIdsBox: await Hive.openBox<String>('chapter_ids'),
      progressBox: await Hive.openBox<String>('progress'),
      historyBox: await Hive.openBox<String>('history'),
      categoriesBox: await Hive.openBox<String>('categories'),
      settingsBox: await Hive.openBox<dynamic>('settings'),
    );
    await service._seedCategories();
    return service;
  }

  Future<void> _seedCategories() async {
    if (categoriesBox.isNotEmpty) return;
    const names = ['En cours', 'Terminé', 'À lire'];
    for (var i = 0; i < names.length; i++) {
      final category = Category(id: 'default_$i', name: names[i], order: i);
      await categoriesBox.put(category.id, jsonEncode(category.toJson()));
    }
  }
}
''',
  'lib/features/browse/browse_providers.dart': r'''
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/models/manga.dart';
import '../../data/sources/manga_source.dart';

/// État du catalogue d'une source : liste paginée + recherche + filtres.
class CatalogState {
  const CatalogState({
    this.sourceId = '',
    this.items = const [],
    this.page = 0,
    this.hasNext = true,
    this.loading = false,
    this.error,
    this.query = const CatalogQuery(),
  });

  final String sourceId;
  final List<Manga> items;
  final int page;
  final bool hasNext;
  final bool loading;
  final Object? error;
  final CatalogQuery query;

  CatalogState copyWith({
    String? sourceId,
    List<Manga>? items,
    int? page,
    bool? hasNext,
    bool? loading,
    Object? error,
    bool clearError = false,
    CatalogQuery? query,
  }) {
    return CatalogState(
      sourceId: sourceId ?? this.sourceId,
      items: items ?? this.items,
      page: page ?? this.page,
      hasNext: hasNext ?? this.hasNext,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      query: query ?? this.query,
    );
  }
}

class CatalogNotifier extends Notifier<CatalogState> {
  int _token = 0;
  String _language = '';

  @override
  CatalogState build() => const CatalogState();

  /// Ouvre le catalogue d'une source (repart de zéro si la source ou la langue change).
  void start(String sourceId) {
    final language = ref.read(settingsProvider).contentLanguage;
    final same = state.sourceId == sourceId && language == _language;
    if (same && (state.items.isNotEmpty || state.loading)) return;
    _language = language;
    state = CatalogState(sourceId: sourceId);
    _loadFirstPage();
  }

  void setQuery(String text) => _changeQuery(state.query.copyWith(text: text));

  void setSort(CatalogSort sort) =>
      _changeQuery(state.query.copyWith(sort: sort));

  void toggleGenre(String genreId) {
    final ids = {...state.query.genreIds};
    if (!ids.add(genreId)) ids.remove(genreId);
    _changeQuery(state.query.copyWith(genreIds: ids));
  }

  void clearFilters() => _changeQuery(CatalogQuery(text: state.query.text));

  void retry() {
    state = state.copyWith(clearError: true);
    if (state.items.isEmpty) {
      _loadFirstPage();
    } else {
      loadMore();
    }
  }

  void _changeQuery(CatalogQuery query) {
    state = state.copyWith(query: query);
    _loadFirstPage();
  }

  Future<void> _loadFirstPage() async {
    final token = ++_token;
    state = state.copyWith(
      items: const [],
      page: 0,
      hasNext: true,
      loading: true,
      clearError: true,
    );
    await _fetch(token, 1);
  }

  /// Charge la page suivante (appelé quand on arrive en bas de la grille).
  Future<void> loadMore() async {
    if (state.loading ||
        !state.hasNext ||
        state.sourceId.isEmpty ||
        state.error != null) {
      return;
    }
    state = state.copyWith(loading: true);
    await _fetch(_token, state.page + 1);
  }

  Future<void> _fetch(int token, int page) async {
    final source = ref.read(sourceByIdProvider(state.sourceId));
    if (source == null) {
      state = state.copyWith(loading: false, error: 'Source introuvable.');
      return;
    }
    try {
      final result = await source.fetchCatalog(page: page, query: state.query);
      if (token != _token) {
        return; // une recherche plus récente a pris le relais
      }
      final known = {for (final m in state.items) m.id};
      state = state.copyWith(
        items: [
          ...state.items,
          ...result.mangas.where((m) => !known.contains(m.id)),
        ],
        page: page,
        hasNext: result.hasNextPage,
        loading: false,
      );
    } catch (e) {
      if (token != _token) return;
      state = state.copyWith(loading: false, error: e);
    }
  }
}

final catalogProvider = NotifierProvider<CatalogNotifier, CatalogState>(
  CatalogNotifier.new,
);

/// Liste des genres d'une source (pour le filtre).
final genresProvider = FutureProvider.family<List<Genre>, String>((
  ref,
  sourceId,
) async {
  final source = ref.watch(sourceByIdProvider(sourceId));
  if (source == null) return const <Genre>[];
  return source.fetchGenres();
});
''',
  'lib/features/browse/catalogue_screen.dart': r'''
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/utils/errors.dart';
import '../../data/models/manga.dart';
import '../../data/sources/manga_source.dart';
import '../../shared/widgets/manga_card.dart';
import '../../shared/widgets/state_views.dart';
import '../details/details_screen.dart';
import 'browse_providers.dart';

/// Catalogue d'une source : grille paginée, recherche, filtres et tri.
class CatalogueScreen extends ConsumerStatefulWidget {
  const CatalogueScreen({super.key, required this.source});

  final MangaSource source;

  @override
  ConsumerState<CatalogueScreen> createState() => _CatalogueScreenState();
}

class _CatalogueScreenState extends ConsumerState<CatalogueScreen> {
  final _scroll = ScrollController();
  final _searchCtrl = TextEditingController();
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // On attend la fin de la construction avant de modifier un provider.
    Future.microtask(() {
      if (mounted) ref.read(catalogProvider.notifier).start(widget.source.id);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 600) {
      ref.read(catalogProvider.notifier).loadMore();
    }
  }

  void _toggleSearch() {
    final hadQuery = ref.read(catalogProvider).query.text.isNotEmpty;
    setState(() => _searching = !_searching);
    if (!_searching) {
      _searchCtrl.clear();
      if (hadQuery) ref.read(catalogProvider.notifier).setQuery('');
    }
  }

  void _openFilters() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FilterSheet(sourceId: widget.source.id),
    );
  }

  void _open(Manga manga) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => MangaDetailsScreen(manga: manga)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(catalogProvider);
    final inLibrary = ref.watch(libraryKeysProvider);
    final ready = state.sourceId == widget.source.id;

    final slivers = <Widget>[
      SliverAppBar(
        floating: true,
        snap: true,
        title: _searching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Rechercher un titre…',
                  border: InputBorder.none,
                ),
                onSubmitted: (v) =>
                    ref.read(catalogProvider.notifier).setQuery(v),
              )
            : Text(widget.source.name),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            tooltip: 'Rechercher',
            onPressed: _toggleSearch,
          ),
          IconButton(
            icon: Badge(
              isLabelVisible: ready && state.query.hasFilters,
              smallSize: 8,
              child: const Icon(Icons.filter_list),
            ),
            tooltip: 'Filtres et tri',
            onPressed: _openFilters,
          ),
        ],
      ),
    ];

    if (!ready || (state.items.isEmpty && state.loading)) {
      slivers.add(
        const SliverFillRemaining(hasScrollBody: false, child: LoadingView()),
      );
    } else if (state.items.isEmpty && state.error != null) {
      slivers.add(
        SliverFillRemaining(
          hasScrollBody: false,
          child: ErrorView(
            message: describeError(state.error!),
            onRetry: () => ref.read(catalogProvider.notifier).retry(),
          ),
        ),
      );
    } else if (state.items.isEmpty) {
      slivers.add(
        const SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyView(message: 'Aucun résultat'),
        ),
      );
    } else {
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 130,
              childAspectRatio: 0.64,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            delegate: SliverChildBuilderDelegate((context, i) {
              final manga = state.items[i];
              return MangaCard(
                manga: manga,
                showStatus: true,
                inLibrary: inLibrary.contains(manga.key),
                onTap: () => _open(manga),
              );
            }, childCount: state.items.length),
          ),
        ),
      );
      slivers.add(SliverToBoxAdapter(child: _footer(state)));
    }

    return Scaffold(
      body: CustomScrollView(controller: _scroll, slivers: slivers),
    );
  }

  Widget _footer(CatalogState state) {
    if (state.loading) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (state.error != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Center(
          child: TextButton.icon(
            onPressed: () => ref.read(catalogProvider.notifier).retry(),
            icon: const Icon(Icons.refresh),
            label: Text('${describeError(state.error!)} Réessayer'),
          ),
        ),
      );
    }
    return const SizedBox(height: 24);
  }
}

/// Panneau de filtres : tri + genres.
class _FilterSheet extends ConsumerWidget {
  const _FilterSheet({required this.sourceId});

  final String sourceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(catalogProvider.select((s) => s.query));
    final genres = ref.watch(genresProvider(sourceId));
    final notifier = ref.read(catalogProvider.notifier);
    final titleStyle = Theme.of(context).textTheme.titleMedium;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('Trier par', style: titleStyle),
                const Spacer(),
                TextButton(
                  onPressed: notifier.clearFilters,
                  child: const Text('Réinitialiser'),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final sort in CatalogSort.values)
                  ChoiceChip(
                    label: Text(sort.label),
                    selected: query.sort == sort,
                    onSelected: (_) => notifier.setSort(sort),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Genres', style: titleStyle),
            const SizedBox(height: 8),
            genres.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text(describeError(e)),
              data: (list) => list.isEmpty
                  ? const Text('Aucun genre disponible pour cette source.')
                  : Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final genre in list)
                          FilterChip(
                            label: Text(genre.name),
                            selected: query.genreIds.contains(genre.id),
                            onSelected: (_) => notifier.toggleGenre(genre.id),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
''',
  'lib/features/browse/sources_screen.dart': r'''
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

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
      appBar: AppBar(title: const Text('Explorer'), actions: [IconButton(tooltip: 'Importer un dossier local', icon: const Icon(Icons.create_new_folder_outlined), onPressed: _importLocal)]),
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

  Future<void> _importLocal() async {
    final path = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Choisir le dossier contenant les mangas');
    if (path == null || !mounted) return;
    ref.read(localSourceProvider).setRoot(path);
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dossier local importé. Ouvre Bibliothèque locale.')));
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
''',
  'lib/features/details/details_providers.dart': r'''
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/models/chapter.dart';
import '../../data/models/manga.dart';

class DetailsData {
  const DetailsData(this.manga, this.chapters);

  final Manga manga;

  /// Chapitres du plus ancien au plus récent.
  final List<Chapter> chapters;
}

/// Charge les infos complètes d'un manga + sa liste de chapitres.
final mangaDetailsProvider = FutureProvider.autoDispose
    .family<DetailsData, Manga>((ref, manga) async {
      final source = ref.watch(sourceByIdProvider(manga.sourceId));
      if (source == null) {
        throw StateError('Source introuvable : ${manga.sourceId}');
      }
      // Recharge automatiquement si la langue des chapitres change.
      ref.watch(settingsProvider.select((s) => s.contentLanguage));

      final full = await source.fetchMangaDetails(manga);
      final chapters = await source.fetchChapters(full);

      // Si le manga est dans la bibliothèque, on met à jour ses infos et son compteur de chapitres.
      await ref.read(libraryRepositoryProvider).syncIfInLibrary(full, [
        for (final c in chapters) c.id,
      ]);

      return DetailsData(full, chapters);
    });
''',
  'lib/features/details/details_screen.dart': r'''
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/format.dart';
import '../../data/models/chapter.dart';
import '../../data/models/manga.dart';
import '../../data/models/manga_progress.dart';
import '../../shared/widgets/cover_image.dart';
import '../../shared/widgets/expandable_text.dart';
import '../../shared/widgets/state_views.dart';
import '../downloads/downloads_provider.dart';
import '../reader/reader_screen.dart';
import 'details_providers.dart';

/// Page d'un manga : en-tête, boutons d'action, synopsis et liste des chapitres.
class MangaDetailsScreen extends ConsumerStatefulWidget {
  const MangaDetailsScreen({super.key, required this.manga});

  final Manga manga;

  @override
  ConsumerState<MangaDetailsScreen> createState() => _MangaDetailsScreenState();
}

class _MangaDetailsScreenState extends ConsumerState<MangaDetailsScreen> {
  final _scroll = ScrollController();
  bool _collapsed = false;
  bool _newestFirst = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final collapsed = _scroll.hasClients && _scroll.offset > 250;
      if (collapsed != _collapsed) setState(() => _collapsed = collapsed);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detailsAsync = ref.watch(mangaDetailsProvider(widget.manga));

    // Dès que les chapitres arrivent, on regarde lesquels sont déjà téléchargés.
    ref.listen<AsyncValue<DetailsData>>(mangaDetailsProvider(widget.manga), (
      previous,
      next,
    ) {
      final data = next.value;
      if (data != null) {
        ref.read(downloadsProvider.notifier).scan(data.manga, data.chapters);
      }
    });

    final data = detailsAsync.value;
    final manga = data?.manga ?? widget.manga;
    final chapters =
        data?.chapters ?? const <Chapter>[]; // du plus ancien au plus récent
    final inLibrary = ref.watch(libraryKeysProvider).contains(manga.key);
    final progress =
        ref.watch(mangaProgressProvider(manga.key)).value ??
        const MangaProgress();
    final downloads = ref.watch(downloadsProvider);
    final shown = _newestFirst ? chapters.reversed.toList() : chapters;

    // Bouton "Lire" : premier chapitre non lu.
    final allRead =
        chapters.isNotEmpty && chapters.every((c) => progress.isRead(c.id));
    final firstUnread = chapters.indexWhere((c) => !progress.isRead(c.id));
    final startIndex = (allRead || firstUnread < 0) ? 0 : firstUnread;
    final String readLabel;
    if (chapters.isEmpty) {
      readLabel = 'Lire';
    } else if (allRead) {
      readLabel = 'Relire';
    } else if (progress.isEmpty) {
      readLabel = 'Lire';
    } else {
      readLabel = 'Continuer · ${chapters[startIndex].displayTitle}';
    }

    return Scaffold(
      body: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 340,
            title: AnimatedOpacity(
              opacity: _collapsed ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: Text(
                manga.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Actualiser',
                onPressed: () =>
                    ref.invalidate(mangaDetailsProvider(widget.manga)),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.parallax,
              background: _Header(manga: manga),
            ),
          ),
          SliverToBoxAdapter(
            child: _actions(
              manga: manga,
              chapters: chapters,
              inLibrary: inLibrary,
              canAdd: data != null || inLibrary,
              readLabel: readLabel,
              startIndex: startIndex,
            ),
          ),
          if (manga.genres.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final genre in manga.genres)
                      Chip(
                        label: Text(genre),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
            ),
          if (manga.description.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: ExpandableText(manga.description),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: [
                  Text(
                    '${chapters.length} chapitre${chapters.length > 1 ? 's' : ''}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.swap_vert),
                    tooltip: "Inverser l'ordre",
                    onPressed: () =>
                        setState(() => _newestFirst = !_newestFirst),
                  ),
                ],
              ),
            ),
          ),
          if (detailsAsync.isLoading && chapters.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (detailsAsync.hasError && chapters.isEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 240,
                child: ErrorView(
                  message: describeError(detailsAsync.error!),
                  onRetry: () =>
                      ref.invalidate(mangaDetailsProvider(widget.manga)),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) =>
                    _tile(manga, shown[i], chapters, progress, downloads),
                childCount: shown.length,
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- widgets

  Widget _actions({
    required Manga manga,
    required List<Chapter> chapters,
    required bool inLibrary,
    required bool canAdd,
    required String readLabel,
    required int startIndex,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: chapters.isEmpty
                  ? null
                  : () => _openReader(manga, chapters, startIndex),
              icon: const Icon(Icons.play_arrow),
              label: Text(
                readLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: canAdd
                      ? () => _toggleLibrary(manga, chapters, inLibrary)
                      : null,
                  icon: Icon(
                    inLibrary ? Icons.favorite : Icons.favorite_border,
                  ),
                  label: Text(
                    inLibrary
                        ? 'Dans la bibliothèque'
                        : 'Ajouter à la bibliothèque',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: chapters.isEmpty
                    ? null
                    : () => _downloadMenu(manga, chapters),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Télécharger'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tile(
    Manga manga,
    Chapter chapter,
    List<Chapter> ascending,
    MangaProgress progress,
    DownloadsState downloads,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final read = progress.isRead(chapter.id);
    final page = progress.pageOf(chapter.id);
    final scanlator = chapter.scanlator;
    final info = <String>[
      if (chapter.publishedAt != null) formatDate(chapter.publishedAt),
      if (scanlator != null && scanlator.isNotEmpty) scanlator,
      if (!read && page > 0) 'page ${page + 1}',
    ];

    return ListTile(
      leading: SizedBox(
        width: 24,
        child: Center(
          child: Icon(
            read ? Icons.done_all : Icons.fiber_manual_record,
            size: read ? 20 : 12,
            color: read ? scheme.outline : scheme.primary,
          ),
        ),
      ),
      title: Text(
        chapter.displayTitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: read ? TextStyle(color: scheme.outline) : null,
      ),
      subtitle: info.isEmpty ? null : Text(info.join(' · ')),
      trailing: _downloadButton(manga, chapter, downloads),
      onTap: () => _openReader(
        manga,
        ascending,
        ascending.indexWhere((c) => c.id == chapter.id),
      ),
      // Appui long = marquer comme lu / non lu.
      onLongPress: () => ref.read(progressRepositoryProvider).setRead(
        manga.key,
        [chapter.id],
        !read,
      ),
    );
  }

  Widget _downloadButton(
    Manga manga,
    Chapter chapter,
    DownloadsState downloads,
  ) {
    final key = DownloadsNotifier.keyOf(manga, chapter);
    final notifier = ref.read(downloadsProvider.notifier);
    final progress = downloads.active[key];

    if (progress != null) {
      return SizedBox(
        width: 40,
        height: 40,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            value: progress > 0 ? progress : null,
          ),
        ),
      );
    }
    if (downloads.done.contains(key)) {
      return IconButton(
        icon: Icon(
          Icons.download_done,
          color: Theme.of(context).colorScheme.primary,
        ),
        tooltip: 'Téléchargé – appuie pour supprimer',
        onPressed: () => notifier.remove(manga, chapter),
      );
    }
    return IconButton(
      icon: Icon(
        downloads.failed.contains(key)
            ? Icons.error_outline
            : Icons.download_outlined,
      ),
      tooltip: 'Télécharger',
      onPressed: () => notifier.enqueue(manga, [chapter]),
    );
  }

  // ----------------------------------------------------------------- actions

  void _openReader(Manga manga, List<Chapter> ascending, int index) {
    if (index < 0) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReaderScreen(
          manga: manga,
          chapters: ascending,
          initialIndex: index,
        ),
      ),
    );
  }

  Future<void> _toggleLibrary(
    Manga manga,
    List<Chapter> chapters,
    bool inLibrary,
  ) async {
    final repo = ref.read(libraryRepositoryProvider);
    if (inLibrary) {
      await repo.remove(manga.key);
    } else {
      await repo.add(manga, chapterIds: [for (final c in chapters) c.id]);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          inLibrary ? 'Retiré de la bibliothèque' : 'Ajouté à la bibliothèque',
        ),
      ),
    );
  }

  void _downloadMenu(Manga manga, List<Chapter> ascending) {
    final progress =
        ref.read(mangaProgressProvider(manga.key)).value ??
        const MangaProgress();
    final unread = ascending.where((c) => !progress.isRead(c.id)).toList();

    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Les 5 prochains chapitres non lus'),
              onTap: () {
                Navigator.pop(ctx);
                _enqueue(manga, unread.take(5).toList());
              },
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Tous les chapitres non lus'),
              onTap: () {
                Navigator.pop(ctx);
                _enqueue(manga, unread);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Tous les chapitres'),
              onTap: () {
                Navigator.pop(ctx);
                _enqueue(manga, ascending);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _enqueue(Manga manga, List<Chapter> chapters) {
    if (chapters.isEmpty) return;
    ref.read(downloadsProvider.notifier).enqueue(manga, chapters);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${chapters.length} chapitre(s) ajouté(s) aux téléchargements',
        ),
      ),
    );
  }
}

/// En-tête immersif : couverture floutée en fond + couverture, titre, auteur, statut.
class _Header extends StatelessWidget {
  const _Header({required this.manga});

  final Manga manga;

  @override
  Widget build(BuildContext context) {
    final cover = manga.coverUrl;
    final author = manga.author;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (cover != null)
          ClipRect(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: CachedNetworkImage(imageUrl: cover, fit: BoxFit.cover),
            ),
          ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black45, Colors.black87],
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, kToolbarHeight, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  width: 120,
                  height: 180,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CoverImage(url: cover),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        manga.title,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (author != null)
                        Text(
                          author,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      Text(
                        manga.status.label,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
''',
  'lib/features/downloads/downloads_provider.dart': r'''
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/models/chapter.dart';
import '../../data/models/manga.dart';

/// État des téléchargements : chapitres terminés, en cours (avec progression) ou en échec.
class DownloadsState {
  const DownloadsState({
    this.done = const {},
    this.active = const {},
    this.failed = const {},
  });

  final Set<String> done;
  final Map<String, double> active;
  final Set<String> failed;

  DownloadsState copyWith({
    Set<String>? done,
    Map<String, double>? active,
    Set<String>? failed,
  }) {
    return DownloadsState(
      done: done ?? this.done,
      active: active ?? this.active,
      failed: failed ?? this.failed,
    );
  }
}

class _Job {
  _Job(this.manga, this.chapter);

  final Manga manga;
  final Chapter chapter;
}

class DownloadsNotifier extends Notifier<DownloadsState> {
  final List<_Job> _queue = [];
  bool _running = false;

  @override
  DownloadsState build() => const DownloadsState();

  /// Clé d'un chapitre dans l'état ("source:idChapitre").
  static String keyOf(Manga manga, Chapter chapter) =>
      '${manga.sourceId}:${chapter.id}';

  /// Regarde sur le disque quels chapitres de ce manga sont déjà téléchargés.
  Future<void> scan(Manga manga, List<Chapter> chapters) async {
    final service = ref.read(downloadServiceProvider);
    final folders = await service.downloadedFolders(manga);
    final found = <String>{
      for (final c in chapters)
        if (folders.contains(service.folderOf(c))) keyOf(manga, c),
    };
    state = state.copyWith(done: {...state.done, ...found});
  }

  /// Ajoute des chapitres à la file de téléchargement (un seul à la fois).
  void enqueue(Manga manga, List<Chapter> chapters) {
    final active = {...state.active};
    final failed = {...state.failed};
    for (final c in chapters) {
      final key = keyOf(manga, c);
      if (state.done.contains(key) || active.containsKey(key)) continue;
      _queue.add(_Job(manga, c));
      active[key] = 0;
      failed.remove(key);
    }
    state = state.copyWith(active: active, failed: failed);
    _run();
  }

  Future<void> _run() async {
    if (_running) return;
    _running = true;
    final service = ref.read(downloadServiceProvider);
    while (_queue.isNotEmpty) {
      final job = _queue.removeAt(0);
      final key = keyOf(job.manga, job.chapter);
      try {
        final source = ref.read(sourceByIdProvider(job.manga.sourceId));
        if (source == null) throw StateError('Source introuvable.');
        await service.downloadChapter(
          source: source,
          manga: job.manga,
          chapter: job.chapter,
          onProgress: (p) =>
              state = state.copyWith(active: {...state.active, key: p}),
        );
        state = state.copyWith(
          done: {...state.done, key},
          active: {...state.active}..remove(key),
        );
      } catch (_) {
        state = state.copyWith(
          failed: {...state.failed, key},
          active: {...state.active}..remove(key),
        );
      }
    }
    _running = false;
  }

  Future<void> remove(Manga manga, Chapter chapter) async {
    await ref.read(downloadServiceProvider).deleteChapter(manga, chapter);
    state = state.copyWith(
      done: {...state.done}..remove(keyOf(manga, chapter)),
    );
  }

  /// À appeler après la suppression de tous les téléchargements.
  void clearDone() => state = state.copyWith(done: <String>{});
}

final downloadsProvider = NotifierProvider<DownloadsNotifier, DownloadsState>(
  DownloadsNotifier.new,
);
''',
  'lib/features/history/history_screen.dart': r'''
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/cover_image.dart';
import '../../shared/widgets/state_views.dart';
import '../details/details_screen.dart';

/// Historique de lecture : un manga par ligne, le plus récent en haut.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historique'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Tout effacer',
            onPressed: () => _confirmClear(context, ref),
          ),
        ],
      ),
      body: history.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(message: describeError(e)),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyView(
              message: 'Rien lu pour le moment.',
              icon: Icons.history,
            );
          }
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, i) {
              final entry = items[i];
              return ListTile(
                leading: SizedBox(
                  width: 46,
                  height: 66,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: CoverImage(url: entry.manga.coverUrl),
                  ),
                ),
                title: Text(
                  entry.manga.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${entry.chapterTitle} · page ${entry.page + 1}\n'
                  '${formatRelative(entry.readAt)}',
                ),
                isThreeLine: true,
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Retirer de l\'historique',
                  onPressed: () => ref
                      .read(historyRepositoryProvider)
                      .remove(entry.manga.key),
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MangaDetailsScreen(manga: entry.manga),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Effacer l'historique ?"),
        content: const Text('Ta progression de lecture est conservée.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Effacer'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(historyRepositoryProvider).clear();
  }
}
''',
  'lib/features/home/home_shell.dart': r'''
import 'package:flutter/material.dart';

import '../browse/sources_screen.dart';
import '../history/history_screen.dart';
import '../library/library_screen.dart';
import '../settings/settings_screen.dart';

/// Barre de navigation du bas : Bibliothèque / Historique / Explorer / Réglages.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _pages = <Widget>[
    LibraryScreen(),
    HistoryScreen(),
    SourcesScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.collections_bookmark_outlined),
            selectedIcon: Icon(Icons.collections_bookmark),
            label: 'Bibliothèque',
          ),
          NavigationDestination(icon: Icon(Icons.history), label: 'Historique'),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Explorer',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Réglages',
          ),
        ],
      ),
    );
  }
}
''',
  'lib/features/library/library_screen.dart': r'''
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/models/category.dart';
import '../../data/models/library_entry.dart';
import '../../data/models/manga.dart';
import '../../data/models/manga_progress.dart';
import '../../shared/widgets/cover_image.dart';
import '../../shared/widgets/manga_card.dart';
import '../../shared/widgets/state_views.dart';
import '../details/details_screen.dart';

/// Bibliothèque : mangas suivis, par catégories, avec badges de chapitres non lus.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _searchCtrl = TextEditingController();
  bool _searching = false;
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  int _unread(LibraryEntry entry, Map<String, MangaProgress> progress) {
    final read = progress[entry.manga.key]?.readChapterIds.length ?? 0;
    final unread = entry.chapterCount - read;
    return unread < 0 ? 0 : unread;
  }

  void _open(LibraryEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MangaDetailsScreen(manga: entry.manga),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(libraryEntriesProvider);
    final categories =
        ref.watch(categoriesProvider).value ?? const <Category>[];
    final progress =
        ref.watch(allProgressProvider).value ?? const <String, MangaProgress>{};
    final grid = ref.watch(settingsProvider.select((s) => s.libraryGrid));
    final entries = entriesAsync.value ?? const <LibraryEntry>[];
    final tabCount = categories.length + 1;

    return DefaultTabController(
      // Nouvelle clé = le contrôleur d'onglets est recréé quand le nombre de catégories change.
      key: ValueKey(tabCount),
      length: tabCount,
      child: Scaffold(
        appBar: AppBar(
          title: _searching
              ? TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Rechercher dans la bibliothèque',
                    border: InputBorder.none,
                  ),
                  onChanged: (v) =>
                      setState(() => _query = v.trim().toLowerCase()),
                )
              : const Text('Bibliothèque'),
          actions: [
            IconButton(
              icon: Icon(_searching ? Icons.close : Icons.search),
              tooltip: 'Rechercher',
              onPressed: () => setState(() {
                _searching = !_searching;
                if (!_searching) {
                  _searchCtrl.clear();
                  _query = '';
                }
              }),
            ),
            IconButton(
              icon: Icon(grid ? Icons.view_list : Icons.grid_view),
              tooltip: grid ? 'Afficher en liste' : 'Afficher en grille',
              onPressed: () =>
                  ref.read(settingsProvider.notifier).setLibraryGrid(!grid),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'refresh') _refresh();
                if (value == 'categories') _manageCategories();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'refresh',
                  child: Text('Actualiser la bibliothèque'),
                ),
                PopupMenuItem(
                  value: 'categories',
                  child: Text('Gérer les catégories'),
                ),
              ],
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              const Tab(text: 'Tous'),
              for (final c in categories) Tab(text: c.name),
            ],
          ),
        ),
        body: entriesAsync.isLoading && entries.isEmpty
            ? const LoadingView()
            : TabBarView(
                children: [
                  for (var i = 0; i < tabCount; i++)
                    _tab(i, categories, entries, progress, grid),
                ],
              ),
      ),
    );
  }

  Widget _tab(
    int index,
    List<Category> categories,
    List<LibraryEntry> entries,
    Map<String, MangaProgress> progress,
    bool grid,
  ) {
    var items = entries;
    if (index > 0) {
      final categoryId = categories[index - 1].id;
      items = items.where((e) => e.categoryIds.contains(categoryId)).toList();
    }
    if (_query.isNotEmpty) {
      items = items
          .where((e) => e.manga.title.toLowerCase().contains(_query))
          .toList();
    }

    Widget body;
    if (items.isEmpty) {
      // Un ListView permet quand même le "tirer pour actualiser".
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: 320,
            child: EmptyView(
              icon: Icons.collections_bookmark_outlined,
              message: entries.isEmpty
                  ? 'Ta bibliothèque est vide.\nVa dans « Explorer » pour ajouter des mangas.'
                  : 'Aucun manga ici.',
            ),
          ),
        ],
      );
    } else {
      body = grid ? _grid(items, progress) : _list(items, progress);
    }
    return RefreshIndicator(onRefresh: _refresh, child: body);
  }

  Widget _grid(List<LibraryEntry> items, Map<String, MangaProgress> progress) {
    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 130,
        childAspectRatio: 0.64,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final entry = items[i];
        return MangaCard(
          manga: entry.manga,
          unread: _unread(entry, progress),
          onTap: () => _open(entry),
          onLongPress: () => _showMenu(entry),
        );
      },
    );
  }

  Widget _list(List<LibraryEntry> items, Map<String, MangaProgress> progress) {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final entry = items[i];
        final unread = _unread(entry, progress);
        return ListTile(
          leading: SizedBox(
            width: 46,
            height: 66,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CoverImage(url: entry.manga.coverUrl),
            ),
          ),
          title: Text(
            entry.manga.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(entry.manga.author ?? entry.manga.status.label),
          trailing: unread > 0 ? Badge(label: Text('$unread')) : null,
          onTap: () => _open(entry),
          onLongPress: () => _showMenu(entry),
        );
      },
    );
  }

  // ---------------------------------------------------------------- actions

  void _showMenu(LibraryEntry entry) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                entry.manga.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.label_outline),
              title: const Text('Changer de catégorie'),
              onTap: () {
                Navigator.pop(ctx);
                _chooseCategories(entry);
              },
            ),
            ListTile(
              leading: const Icon(Icons.done_all),
              title: const Text('Marquer comme lu'),
              onTap: () {
                Navigator.pop(ctx);
                _markAll(entry, true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.remove_done),
              title: const Text('Marquer comme non lu'),
              onTap: () {
                Navigator.pop(ctx);
                _markAll(entry, false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Retirer de la bibliothèque'),
              onTap: () {
                Navigator.pop(ctx);
                _remove(entry);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _markAll(LibraryEntry entry, bool read) async {
    final ids = ref.read(libraryRepositoryProvider).chapterIds(entry.manga.key);
    await ref
        .read(progressRepositoryProvider)
        .setRead(entry.manga.key, ids, read);
  }

  Future<void> _remove(LibraryEntry entry) async {
    await ref.read(libraryRepositoryProvider).remove(entry.manga.key);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('« ${entry.manga.title} » retiré de la bibliothèque'),
      ),
    );
  }

  Future<void> _chooseCategories(LibraryEntry entry) async {
    final categories = ref.read(categoriesProvider).value ?? const <Category>[];
    if (categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Crée d'abord une catégorie (menu ⋮).")),
      );
      return;
    }
    final selected = {...entry.categoryIds};
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Catégories'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final c in categories)
                  CheckboxListTile(
                    value: selected.contains(c.id),
                    title: Text(c.name),
                    onChanged: (v) => setLocal(() {
                      if (v == true) {
                        selected.add(c.id);
                      } else {
                        selected.remove(c.id);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, selected),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      await ref
          .read(libraryRepositoryProvider)
          .setCategories(entry.manga.key, result.toList());
    }
  }

  void _manageCategories() {
    showDialog<void>(
      context: context,
      builder: (_) => const _CategoriesDialog(),
    );
  }

  /// Recharge la liste des chapitres de chaque manga pour mettre à jour les badges.
  Future<void> _refresh() async {
    final entries =
        ref.read(libraryEntriesProvider).value ?? const <LibraryEntry>[];
    final repo = ref.read(libraryRepositoryProvider);
    for (final entry in entries) {
      final source = ref.read(sourceByIdProvider(entry.manga.sourceId));
      if (source == null) continue;
      try {
        final chapters = await source.fetchChapters(entry.manga);
        await repo.saveChapterIds(entry.manga.key, [
          for (final c in chapters) c.id,
        ]);
      } catch (_) {
        // erreur réseau : on passe au manga suivant
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Bibliothèque mise à jour')));
  }
}

/// Boîte de dialogue pour ajouter / supprimer des catégories.
class _CategoriesDialog extends ConsumerStatefulWidget {
  const _CategoriesDialog();

  @override
  ConsumerState<_CategoriesDialog> createState() => _CategoriesDialogState();
}

class _CategoriesDialogState extends ConsumerState<_CategoriesDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final name = _ctrl.text.trim();
    if (name.isEmpty) return;
    await ref.read(categoryRepositoryProvider).add(name);
    _ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final categories =
        ref.watch(categoriesProvider).value ?? const <Category>[];
    return AlertDialog(
      title: const Text('Catégories'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final c in categories)
                ListTile(
                  dense: true,
                  title: Text(c.name),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () =>
                        ref.read(categoryRepositoryProvider).delete(c.id),
                  ),
                ),
              TextField(
                controller: _ctrl,
                decoration: InputDecoration(
                  hintText: 'Nouvelle catégorie',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: _add,
                  ),
                ),
                onSubmitted: (_) => _add(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}
''',
  'lib/features/reader/reader_screen.dart': r'''
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
      if (pages.isEmpty) {
        throw StateError('Ce chapitre ne contient aucune page.');
      }

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
        errorBuilder: (_, _, _) => _errorWidget(),
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
''',
  'lib/features/reader/zoomable_view.dart': r'''
import 'package:flutter/material.dart';

/// Page zoomable (pincer pour zoomer). Un appui simple :
/// - remet le zoom à zéro s'il est actif ;
/// - sinon transmet la position du doigt au lecteur (zones gauche / centre / droite).
class ZoomableView extends StatefulWidget {
  const ZoomableView({
    super.key,
    required this.child,
    required this.onTap,
    required this.onZoomChanged,
  });

  final Widget child;
  final ValueChanged<Offset> onTap;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<ZoomableView> createState() => _ZoomableViewState();
}

class _ZoomableViewState extends State<ZoomableView> {
  final TransformationController _controller = TransformationController();
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTransform);
  }

  void _onTransform() {
    final zoomed = _controller.value.getMaxScaleOnAxis() > 1.02;
    if (zoomed == _zoomed) return;
    _zoomed = zoomed;
    widget.onZoomChanged(zoomed);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTransform);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) {
        if (_zoomed) {
          _controller.value = Matrix4.identity();
        } else {
          widget.onTap(details.globalPosition);
        }
      },
      child: InteractiveViewer(
        transformationController: _controller,
        minScale: 1,
        maxScale: 4,
        child: SizedBox.expand(child: widget.child),
      ),
    );
  }
}
''',
  'lib/features/settings/settings_screen.dart': r'''
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
''',
  'lib/features/settings/storage_info_provider.dart': r'''
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/providers.dart';
import '../../core/utils/files.dart';

class StorageInfo {
  const StorageInfo({required this.cacheBytes, required this.downloadBytes});

  final int cacheBytes;
  final int downloadBytes;
}

/// Espace occupé par le cache des images et par les chapitres téléchargés.
final storageInfoProvider = FutureProvider.autoDispose<StorageInfo>((
  ref,
) async {
  final temp = await getTemporaryDirectory();
  // Dossier utilisé par cached_network_image (flutter_cache_manager).
  final cache = await directorySize(
    Directory('${temp.path}/libCachedImageData'),
  );
  final downloads = await ref.read(downloadServiceProvider).totalSize();
  return StorageInfo(cacheBytes: cache, downloadBytes: downloads);
});
''',
  'lib/main.dart': r'''
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/providers.dart';
import 'data/storage/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // On ouvre la base de données locale AVANT de lancer l'interface.
  final storage = await StorageService.init();
  runApp(
    ProviderScope(
      overrides: [storageProvider.overrideWithValue(storage)],
      child: const MangaReaderApp(),
    ),
  );
}
''',
  'lib/shared/widgets/choice_sheet.dart': r'''
import 'package:flutter/material.dart';

/// Affiche une liste de choix dans un panneau en bas de l'écran.
/// Renvoie la valeur choisie (ou null si l'utilisateur ferme le panneau).
Future<T?> showChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required List<(T, String)> options,
  required T selected,
}) {
  return showModalBottomSheet<T>(
    context: context,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(title, style: Theme.of(ctx).textTheme.titleMedium),
            ),
            for (final option in options)
              ListTile(
                title: Text(option.$2),
                trailing: option.$1 == selected
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(ctx, option.$1),
              ),
          ],
        ),
      ),
    ),
  );
}
''',
  'lib/shared/widgets/cover_image.dart': r'''
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Image de couverture mise en cache sur le disque (cached_network_image).
class CoverImage extends StatelessWidget {
  const CoverImage({super.key, required this.url, this.fit = BoxFit.cover});

  final String? url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final address = url;
    if (address == null || address.isEmpty) {
      return const _CoverPlaceholder(icon: Icons.menu_book_outlined);
    }
    return CachedNetworkImage(
      imageUrl: address,
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 150),
      fadeOutDuration: const Duration(milliseconds: 100),
      placeholder: (context, _) => const _CoverPlaceholder(),
      errorWidget: (context, _, _) =>
          const _CoverPlaceholder(icon: Icons.broken_image_outlined),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder({this.icon});

  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: kPlaceholderColor,
      child: icon == null
          ? null
          : Center(child: Icon(icon, color: Colors.white54)),
    );
  }
}
''',
  'lib/shared/widgets/expandable_text.dart': r'''
import 'package:flutter/material.dart';

/// Texte limité à quelques lignes, avec un bouton "Lire la suite".
class ExpandableText extends StatefulWidget {
  const ExpandableText(this.text, {super.key, this.collapsedLines = 4});

  final String text;
  final int collapsedLines;

  @override
  State<ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isLong = widget.text.length > 180;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: Text(
            widget.text,
            maxLines: _expanded ? null : widget.collapsedLines,
            overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          ),
        ),
        if (isLong)
          TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            child: Text(_expanded ? 'Réduire' : 'Lire la suite'),
          ),
      ],
    );
  }
}
''',
  'lib/shared/widgets/manga_card.dart': r'''
import 'package:flutter/material.dart';

import '../../data/models/manga.dart';
import 'cover_image.dart';

/// Carte "couverture + titre" utilisée dans la bibliothèque et les catalogues.
class MangaCard extends StatelessWidget {
  const MangaCard({
    super.key,
    required this.manga,
    required this.onTap,
    this.onLongPress,
    this.unread = 0,
    this.inLibrary = false,
    this.showStatus = false,
  });

  final Manga manga;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Nombre de chapitres non lus (badge en haut à gauche).
  final int unread;

  /// Affiche une pastille "déjà dans la bibliothèque".
  final bool inLibrary;

  /// Affiche le statut (En cours / Terminé…) en haut à droite.
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CoverImage(url: manga.coverUrl),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.center,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black87],
              ),
            ),
          ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Text(
              manga.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.15,
              ),
            ),
          ),
          Positioned(
            top: 6,
            left: 6,
            child: Wrap(
              spacing: 4,
              children: [
                if (unread > 0)
                  _CoverBadge(
                    text: '$unread',
                    background: scheme.primary,
                    foreground: scheme.onPrimary,
                  ),
                if (inLibrary)
                  _CoverBadge(
                    icon: Icons.favorite,
                    background: scheme.tertiary,
                    foreground: scheme.onTertiary,
                  ),
              ],
            ),
          ),
          if (showStatus)
            Positioned(
              top: 6,
              right: 6,
              child: _CoverBadge(
                text: manga.status.label,
                background: Colors.black54,
                foreground: Colors.white,
              ),
            ),
          // Zone cliquable avec effet "ripple" au-dessus de l'image.
          Positioned.fill(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(onTap: onTap, onLongPress: onLongPress),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverBadge extends StatelessWidget {
  const _CoverBadge({
    this.text,
    this.icon,
    required this.background,
    required this.foreground,
  });

  final String? text;
  final IconData? icon;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final label = text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: label != null
          ? Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            )
          : Icon(icon, size: 12, color: foreground),
    );
  }
}
''',
  'lib/shared/widgets/state_views.dart': r'''
import 'package:flutter/material.dart';

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.message, this.icon});

  final String message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon ?? Icons.inbox_outlined, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
''',
};
