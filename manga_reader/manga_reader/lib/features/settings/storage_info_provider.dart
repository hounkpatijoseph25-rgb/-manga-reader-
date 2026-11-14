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
