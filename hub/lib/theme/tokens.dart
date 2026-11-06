import 'package:flutter/widgets.dart';

/// Tokens du design system ThibsDarts "Golden Hour Urbex".
/// Source : tokens.css du design system (artifact Claude Design).
abstract final class Td {
  // Couleurs
  static const beton = Color(0xFF121214);
  static const betonNuit = Color(0xFF0B0B0D);
  static const asphalte = Color(0xFF1E1F24);
  static const asphalteHaut = Color(0xFF2A2B31);
  static const sunset = Color(0xFFFF7A2F);
  static const crepuscule = Color(0xFFFF4D8D);
  static const ciel = Color(0xFF4FA3FF);
  static const fluo = Color(0xFFFFE14D);
  static const onAccent = Color(0xFF121214);
  static const ink = Color(0xFFF5F3EE);
  static const ink2 = Color(0xFFB9B9C2);
  static const ink3 = Color(0xFF94959F);
  static const succes = Color(0xFF3DDC97);
  static const erreur = Color(0xFFFF6464);
  static const desactiveInk = Color(0xFF6C6D76);
  static const bord = Color(0x1AFFFFFF);
  static const verreLeger = Color(0x0DFFFFFF);
  static const verreMoyen = Color(0x17FFFFFF);
  static const verreFort = Color(0xB826272E);
  static const verreBord = Color(0x29FFFFFF);
  static const voile = Color(0x9E08080A);

  // Plateau
  static const plateauNoir = Color(0xFF17181C);
  static const plateauCreme = Color(0xFFE8DCC4);
  static const plateauRouge = Color(0xFFE8434F);
  static const plateauVert = Color(0xFF0C6A55);
  static const plateauFil = Color(0xFF3A3B42);
  static const plateauNumero = Color(0xFFD9D7D0);

  static const goldenHour = LinearGradient(
    colors: [sunset, crepuscule],
    begin: Alignment(-0.9, -0.5),
    end: Alignment(0.9, 0.5),
  );

  // Espacements (grille de 4)
  static const s1 = 4.0, s2 = 8.0, s3 = 12.0, s4 = 16.0, s5 = 20.0, s6 = 24.0, s8 = 32.0;

  // Rayons
  static const rSm = 10.0, rMd = 14.0, rLg = 20.0, rXl = 28.0;

  // Cibles tactiles Pi
  static const ciblePi = 72.0;
  static const ciblePiFort = 96.0;

  // Durées
  static const rapide = Duration(milliseconds: 180);
  static const base = Duration(milliseconds: 280);
  static const lente = Duration(milliseconds: 480);
  static const courbeSortie = Cubic(0.2, 0.8, 0.2, 1);
}

/// Styles de texte. Inter pour l'UI, Nunito pour les scores, Permanent Marker pour les tags.
abstract final class TdText {
  static TextStyle _v(String family, double size, double height, int weight, Color color,
          {double spacing = 0}) =>
      TextStyle(
        fontFamily: family,
        fontSize: size,
        height: height / size,
        fontWeight: FontWeight.values[(weight ~/ 100) - 1],
        fontVariations: [FontVariation.weight(weight.toDouble())],
        letterSpacing: spacing,
        color: color,
      );

  static TextStyle title = _v('Inter', 34, 41, 800, Td.ink, spacing: -0.5);
  static TextStyle headline = _v('Inter', 22, 28, 700, Td.ink);
  static TextStyle body = _v('Inter', 17, 22, 400, Td.ink2);
  static TextStyle label = _v('Inter', 13, 18, 600, Td.ink2);
  static TextStyle caption = _v('Inter', 13, 18, 400, Td.ink3);
  static TextStyle button = _v('Inter', 24, 30, 700, Td.ink);
  static TextStyle score = _v('Nunito', 120, 120, 900, Td.ink,
      ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
  static TextStyle tag = const TextStyle(fontFamily: 'PermanentMarker', fontSize: 64, color: Td.ink);
}
