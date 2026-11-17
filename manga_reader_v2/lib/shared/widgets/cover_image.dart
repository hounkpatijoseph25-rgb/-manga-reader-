import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';

/// Image de couverture : mise en cache sur le disque (cached_network_image)
/// pour les URL http(s), lecture directe pour un chemin de fichier local.
///
/// Les en-têtes nécessaires (Referer du CDN) sont joints via
/// `urlHeadersProvider`.
class CoverImage extends ConsumerWidget {
  const CoverImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.semanticLabel,
  });

  final String? url;
  final BoxFit fit;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = _resolve(context, ref);
    final label = semanticLabel;
    if (label == null) return ExcludeSemantics(child: image);
    return Semantics(image: true, label: label, child: image);
  }

  Widget _resolve(BuildContext context, WidgetRef ref) {
    final address = url;
    if (address == null || address.isEmpty) {
      return const _CoverPlaceholder(icon: Icons.menu_book_outlined);
    }
    if (!address.startsWith('http')) {
      final path = address.startsWith('file://')
          ? Uri.parse(address).toFilePath()
          : address;
      return Image.file(
        File(path),
        fit: fit,
        // Une couverture est affichée en petit : inutile de décoder une page
        // de webtoon en pleine résolution (mémoire et rapidité).
        cacheWidth: 1080,
        errorBuilder: (context, _, _) =>
            const _CoverPlaceholder(icon: Icons.broken_image_outlined),
      );
    }
    // Couverture déjà recopiée sur l'appareil : elle reste visible même sans
    // connexion.
    final cachedPath = ref.watch(coverIndexProvider)[address];
    if (cachedPath != null) {
      return Image.file(
        File(cachedPath),
        fit: fit,
        cacheWidth: 1080,
        errorBuilder: (context, _, _) =>
            const _CoverPlaceholder(icon: Icons.broken_image_outlined),
      );
    }
    return CachedNetworkImage(
      imageUrl: address,
      fit: fit,
      httpHeaders: ref.watch(urlHeadersProvider)(address),
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
