/// Petits utilitaires partagés par les sources qui lisent du HTML.
///
/// Volontairement sans dépendance : les sites visés ont un balisage stable et
/// régulier, une extraction ciblée suffit et évite d'embarquer un parseur HTML
/// complet dans l'application.
library;

const Map<String, String> _entities = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
  'rsquo': '’',
  'lsquo': '‘',
  'rdquo': '”',
  'ldquo': '“',
  'sbquo': '‚',
  'hellip': '…',
  'mdash': '—',
  'ndash': '–',
  'laquo': '«',
  'raquo': '»',
  'bull': '•',
  'middot': '·',
  'deg': '°',
  'times': '×',
  'copy': '©',
  'reg': '®',
  'trade': '™',
  'euro': '€',
  'pound': '£',
  'eacute': 'é',
  'egrave': 'è',
  'ecirc': 'ê',
  'euml': 'ë',
  'agrave': 'à',
  'acirc': 'â',
  'auml': 'ä',
  'aacute': 'á',
  'ccedil': 'ç',
  'icirc': 'î',
  'iacute': 'í',
  'iuml': 'ï',
  'ocirc': 'ô',
  'oacute': 'ó',
  'ouml': 'ö',
  'ugrave': 'ù',
  'ucirc': 'û',
  'uuml': 'ü',
  'ugrave_': 'ù',
  'yuml': 'ÿ',
  'ntilde': 'ñ',
  'szlig': 'ß',
};

/// Décode les entités HTML (`&amp;`, `&#039;`, `&#x27;`, `&rsquo;`…).
String decodeHtmlEntities(String input) {
  if (!input.contains('&')) return input;
  var out = input.replaceAllMapped(
    RegExp(r'&#x([0-9a-fA-F]+);'),
    (m) => _fromCodePoint(int.parse(m[1]!, radix: 16)),
  );
  out = out.replaceAllMapped(
    RegExp(r'&#(\d+);'),
    (m) => _fromCodePoint(int.parse(m[1]!)),
  );
  return out.replaceAllMapped(RegExp(r'&([a-zA-Z][a-zA-Z0-9]*);'), (m) {
    final value = _entities[m[1]!.toLowerCase()];
    return value ?? m[0]!;
  });
}

String _fromCodePoint(int code) {
  if (code <= 0 || code > 0x10FFFF) return '';
  return String.fromCharCode(code);
}

/// Retire les balises et normalise les espaces d'un fragment HTML.
String stripHtml(String input) {
  var text = input
      .replaceAll(
        RegExp(
          r'<(script|style)[^>]*>.*?</\1>',
          dotAll: true,
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(p|div|li|h[1-6])>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), ' ');
  text = decodeHtmlEntities(text);
  return text
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'[ \t\u00A0]+'), ' ').trim())
      .where((line) => line.isNotEmpty)
      .join('\n')
      .trim();
}

/// Espaces compactés sur une seule ligne (titres, libellés).
String cleanText(String input) =>
    decodeHtmlEntities(input).replaceAll(RegExp(r'\s+'), ' ').trim();

const Map<String, int> _months = {
  'janvier': 1,
  'fevrier': 2,
  'février': 2,
  'mars': 3,
  'avril': 4,
  'mai': 5,
  'juin': 6,
  'juillet': 7,
  'aout': 8,
  'août': 8,
  'septembre': 9,
  'octobre': 10,
  'novembre': 11,
  'decembre': 12,
  'décembre': 12,
};

/// `10 août 2022`, `3 novembre 2026`, `20/10/26` → [DateTime].
DateTime? parseFrenchDate(String input) {
  final text = cleanText(input);
  if (text.isEmpty) return null;
  final iso = DateTime.tryParse(text);
  if (iso != null) return iso;

  final short = RegExp(r'(\d{1,2})/(\d{1,2})/(\d{2,4})').firstMatch(text);
  if (short != null) {
    final day = int.parse(short[1]!);
    final month = int.parse(short[2]!);
    var year = int.parse(short[3]!);
    if (year < 100) year += 2000;
    return _safeDate(year, month, day);
  }

  final long = RegExp(r'(\d{1,2})\s+([A-Za-zÀ-ÿ]+)\s+(\d{4})').firstMatch(text);
  if (long != null) {
    final month = _months[long[2]!.toLowerCase()];
    if (month != null) {
      return _safeDate(int.parse(long[3]!), month, int.parse(long[1]!));
    }
  }
  return null;
}

DateTime? _safeDate(int year, int month, int day) {
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final date = DateTime(year, month, day);
  if (date.month != month || date.day != day) return null;
  return date;
}

/// Transforme un `href` relatif en URL absolue.
String absoluteUrl(String base, String href) {
  final value = href.trim();
  if (value.isEmpty) return base;
  if (value.startsWith('http://') || value.startsWith('https://')) return value;
  if (value.startsWith('//')) return 'https:$value';
  if (value.startsWith('/')) return '$base$value';
  return '$base/$value';
}

/// Dernier segment non vide d'une URL (`/oeuvre/mon-manga/` → `mon-manga`).
String lastUrlSegment(String url) {
  final path = Uri.tryParse(url)?.path ?? url;
  final parts = path.split('/').where((p) => p.trim().isNotEmpty).toList();
  return parts.isEmpty ? '' : parts.last;
}

/// Segment qui suit [marker] (`/oeuvre/mon-manga/` + `oeuvre` → `mon-manga`).
String segmentAfter(String url, String marker) {
  final path = Uri.tryParse(url)?.path ?? url;
  final parts = path.split('/').where((p) => p.trim().isNotEmpty).toList();
  final index = parts.indexOf(marker);
  if (index >= 0 && index + 1 < parts.length) return parts[index + 1];
  return parts.isEmpty ? '' : parts.last;
}

/// Premier groupe capturé d'une expression, ou `null`.
String? firstGroup(String html, Pattern pattern, [int group = 1]) {
  final match = RegExp(pattern.toString(), dotAll: true).firstMatch(html);
  return match?.group(group);
}

/// Tous les groupes 1 d'une expression, dans l'ordre du document.
List<String> allGroups(String html, String pattern) => [
  for (final m in RegExp(pattern, dotAll: true).allMatches(html))
    if (m.groupCount >= 1 && m[1] != null) m[1]!,
];
