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
