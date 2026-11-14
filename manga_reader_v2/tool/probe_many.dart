// Sonde multi-sites (temporaire) : teste la joignabilité depuis Dart/Dio.
import 'package:dio/dio.dart';

const browserHeaders = {
  'User-Agent':
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/122.0 Mobile Safari/537.36',
  'Accept':
      'text/html,application/xhtml+xml,application/xml;q=0.9,'
      'image/avif,image/webp,*/*;q=0.8',
  'Accept-Language': 'fr-FR,fr;q=0.9,en;q=0.8',
  'Upgrade-Insecure-Requests': '1',
};

Future<void> main(List<String> urls) async {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 20),
      headers: browserHeaders,
      validateStatus: (_) => true,
      followRedirects: true,
      responseType: ResponseType.plain,
    ),
  );
  for (final url in urls) {
    try {
      final res = await dio.get<String>(url);
      final body = res.data ?? '';
      final flags = <String>[];
      if (body.contains('Just a moment')) flags.add('CLOUDFLARE');
      if (body.contains('ori-card')) flags.add('origenes-theme');
      if (body.contains('wp-manga')) flags.add('madara');
      if (body.contains('bsx') || body.contains('ts-post-image')) {
        flags.add('mangastream');
      }
      if (body.contains('chapterlist')) flags.add('chapterlist');
      if (body.contains('id="readerarea"')) flags.add('readerarea');
      final title = RegExp(
        r'<title[^>]*>(.*?)</title>',
        dotAll: true,
      ).firstMatch(body)?.group(1);
      print(
        '${res.statusCode} ${body.length} ${res.realUri} '
        '[${flags.join(",")}] ${(title ?? '').trim()}',
      );
    } on DioException catch (e) {
      print('ERR ${e.response?.statusCode} ${e.type.name} $url  (${e.error})');
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
}
