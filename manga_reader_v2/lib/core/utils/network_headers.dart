/// En-têtes à joindre à une image (ou une requête) selon son URL.
///
/// Le CDN de Sushiscan refuse le hotlinking (403) : un Referer suffit.
Map<String, String> headersForUrl(String url) {
  if (_sushiscanPrefixes.any(url.startsWith)) {
    return const {'Referer': 'https://sushiscan.net/'};
  }
  return const {};
}

const _sushiscanPrefixes = [
  'https://sushiscan.net/',
  'https://c.sushiscan.net/',
];
