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
