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
      errorWidget: (context, _, __) =>
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
