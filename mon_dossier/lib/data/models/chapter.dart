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
