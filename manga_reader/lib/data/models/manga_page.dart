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
