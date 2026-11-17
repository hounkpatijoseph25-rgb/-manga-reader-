/// En-têtes à joindre à une image (ou une requête) selon son URL.
///
/// Plusieurs CDN refusent le hotlinking (403) : un `Referer` suffit. On le
/// déduit du domaine, ce qui couvre aussi les sous-domaines d'images
/// (`c.sushiscan.net`, `i.nhentai.net`, …) et pas seulement la page du site.
Map<String, String> headersForUrl(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  if (host.isEmpty) return const {};
  for (final entry in _referers.entries) {
    if (host == entry.key || host.endsWith('.${entry.key}')) {
      return {'Referer': entry.value};
    }
  }
  return const {};
}

/// Domaine du site → page à utiliser comme `Referer`.
const _referers = <String, String>{
  'sushiscan.net': 'https://sushiscan.net/',
  'scan-vf.net': 'https://www.scan-vf.net/',
  'lelscan.net': 'https://lelscan.net/',
  'poseidon-scans.net': 'https://poseidon-scans.net/',
};
