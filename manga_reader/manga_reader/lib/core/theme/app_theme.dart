import 'package:flutter/material.dart';

/// Couleurs principales proposées dans les paramètres.
const List<Color> kSeedColors = [
  Color(0xFF6750A4),
  Color(0xFF1565C0),
  Color(0xFF00897B),
  Color(0xFF2E7D32),
  Color(0xFFEF6C00),
  Color(0xFFD81B60),
  Color(0xFFC62828),
  Color(0xFF455A64),
];

/// Gris semi-transparent, lisible en thème clair comme en thème sombre.
const Color kPlaceholderColor = Color(0x33808080);

ThemeData buildTheme(Color seed, Brightness brightness) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: brightness),
  );
}
