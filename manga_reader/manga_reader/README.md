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
