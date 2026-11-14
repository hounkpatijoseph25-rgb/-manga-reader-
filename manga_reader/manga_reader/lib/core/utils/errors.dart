import 'package:dio/dio.dart';

/// Transforme une erreur technique en message compréhensible.
String describeError(Object error) {
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Le serveur met trop de temps à répondre.';
      case DioExceptionType.connectionError:
        return 'Pas de connexion internet.';
      case DioExceptionType.badResponse:
        final code = error.response?.statusCode;
        if (code == 429) return 'Trop de requêtes, réessaie dans un instant.';
        return 'Erreur du serveur (code ${code ?? '?'}).';
      default:
        return 'Impossible de contacter le serveur.';
    }
  }
  return error.toString().replaceFirst('Exception: ', '');
}
