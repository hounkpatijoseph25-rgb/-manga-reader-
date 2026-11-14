# Manga Reader

Lecteur de manga / manhwa écrit en Flutter. Projet personnel.
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
| `data/sources/` | Les sources : `MangaSource` (interface), `MangaDexSource`, `MangasOriginesSource`, `SushiscanSource`, `ScanVfSource`, `LelscanSource`, `PoseidonScansSource`, `LocalMangaSource` et `scrape_utils.dart` (helpers de scraping) |
| `data/downloads/` | Téléchargement des chapitres pour la lecture hors connexion |
| `features/` | Un dossier par écran : library, browse, details, reader, history, downloads, settings |
| `shared/widgets/` | Widgets réutilisés (carte de manga, couverture, états vides/erreur…) |

## Sources intégrées

| Source | Type | Catalogue | Recherche | Genres |
|---|---|---|---|---|
| MangaDex | API officielle | oui (tri popularité / récent / titre) | oui | oui |
| Mangas Origines (`mangas-origines.fr`) | scraping HTML | oui | oui | oui |
| Sushiscan (`sushiscan.net`) | scraping HTML | oui | oui | oui |
| Scan-VF (`scan-vf.net`) | scraping HTML | oui (catégories + pagination) | oui | oui |
| Lelscan (`lelscan.net`) | scraping HTML | oui | filtrage local | — |
| Poseidon Scans (`poseidon-scans.net`) | Next.js (charge RSC) | oui (API dernières sorties + catalogue paginé) | oui | — |
| Dossier local | fichiers | — | — | — |

Mangas Origines, Sushiscan, Scan-VF et Lelscan n'ont pas d'API publique : les
pages HTML sont lues directement (`lib/data/sources/scrape_utils.dart`). Le tri
du catalogue de ces sites est imposé par le site, le tri choisi dans
l'application n'y est donc pas appliqué.

Poseidon Scans est un site Next.js : les données (auteur, statut, catégories,
chapitres, images) sont lues dans la charge RSC renvoyée avec l'en-tête
`RSC: 1`. Les chapitres encore « premium » ne sont pas listés ; les autres sont
lisibles sans compte.

Le CDN de Sushiscan refuse les images sans en-tête `Referer` : l'application
l'ajoute automatiquement pour ce domaine (voir `headersForUrl` dans
`lib/core/utils/network_headers.dart`), y compris pour les couvertures mises en
cache hors connexion.

Les sites `toonfr.com` et `mangafire.to` sont protégés par un challenge
Cloudflare : ils ne peuvent pas être interrogés simplement et ne sont pas
intégrés (une note le rappelle dans l'onglet Explorer). `mangas-origines.fr` et
`hentai-origines.fr` renvoient un handshake/challenge TLS à Dart (inaccessibles
depuis l'application, bien qu'un navigateur les ouvre) ; `poseidonscans.fr` est
un domaine parké, la source actuelle est `poseidon-scans.net`.

## Bibliothèque locale

Le dossier est choisi depuis **Explorer** (icône dossier) ou **Paramètres › Bibliothèque locale › Dossier des mangas**. Il est enregistré dans les réglages et rechargé au démarrage ; le menu ⋮ de la source permet de changer ou d'oublier le dossier.

Au premier import, Android demande l'autorisation **« Accès à tous les fichiers »** :
sans elle, l'application ne peut pas lire les dossiers situés sur la carte SD ou
dans le stockage partagé (le message « Dossier illisible » l'indique clairement).

Chaque sous-dossier du répertoire choisi est un manga ; ses chapitres sont
**détectés récursivement** : un sous-dossier qui contient directement des images
est un chapitre, sinon on descend dans l'arborescence (jusqu'à 8 niveaux). Les
fichiers `.cbz` / `.zip` sont aussi acceptés comme chapitres et décompressés à la
lecture. Le tri est « naturel » (Chapitre 2 avant Chapitre 10).

Images prises en charge : JPG, JPEG, PNG, WEBP, GIF, BMP, AVIF.

Image de présentation : depuis la fiche du manga (icône image en haut à droite),
on peut choisir **n'importe quelle image du dossier** (aperçus proposés) ou
**une image du téléphone** (copiée dans les données de l'application pour être
conservée même si le fichier d'origine est déplacé). À défaut, l'application
utilise `cover.jpg` / `folder.jpg` / `poster.jpg` / `thumbnail.jpg` /
`default.jpg` à la racine, sinon la première image du dossier.

Le choix est immédiatement répercuté sur la fiche **et** sur la carte de la
bibliothèque : l'entrée enregistrée est mise à jour (couverture recalculée par
la source locale), donc plus d'ancienne image résiduelle.

## Mise à jour automatique et couvertures hors connexion

Au lancement, l'application relit en arrière-plan la liste des chapitres de chaque
manga suivi : les nouveaux chapitres sont enregistrés, les compteurs de la
bibliothèque sont corrigés et un message les signale. L'action
**Bibliothèque › ⋮ › Actualiser la bibliothèque** relance la même mise à jour à la
demande (un indicateur tourne dans la barre du haut pendant l'opération).

Chaque couverture est recopiée dans les données de l'application
(`covers/index.json` + fichiers image) au moment du rafraîchissement : les
couvertures de la bibliothèque restent donc visibles même sans connexion.
L'image de présentation choisie pour un manga local est conservée de la même
façon.

## Ajouter une source

1. Crée `lib/data/sources/ma_source.dart` avec une classe qui `implements MangaSource`
   (regarde `mangadex_source.dart` pour une API, `madara_source.dart` ou
   `sushiscan_source.dart` pour du scraping HTML — les helpers communs sont dans
   `scrape_utils.dart` : décodage d'entités, nettoyage de balises, dates FR, URL absolues).
2. Ajoute-la dans la liste `sourcesProvider` de `lib/core/providers.dart`.

Elle apparaît alors dans l'onglet « Explorer ».

## Remarques

- La source MangaDex utilise l'API publique officielle (contenus « safe » et « suggestive »).
- Les téléchargements ne tournent que lorsque l'application est ouverte.
- Gestion d'état : Riverpod 2.x (volontairement figé sur `^2.6.1`).
