import 'dart:io';

import 'package:flutter/material.dart';

import 'screens/boot_screen.dart';
import 'theme/tokens.dart';
import 'widgets/music_button.dart';

void main() => runApp(const DartOsApp());

/// Largeur d'un pixel de l'écran rapportée à sa hauteur. Les petites dalles 1024x600 (7")
/// ont des pixels un peu plus larges que hauts : sans correction, la cible sort ovale.
/// Réglé par DARTOS_PIXEL_ASPECT dans le service du Pi (ex. 1.05), 1 par défaut.
final _navigator = GlobalKey<NavigatorState>();

final double pixelAspect = double.tryParse(Platform.environment['DARTOS_PIXEL_ASPECT'] ?? '') ?? 1;

class DartOsApp extends StatelessWidget {
  const DartOsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dart OS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Td.beton,
        fontFamily: 'Inter',
        colorScheme: const ColorScheme.dark(primary: Td.sunset, secondary: Td.crepuscule, surface: Td.asphalte),
      ),
      home: const Scaffold(body: BootScreen()),
      navigatorKey: _navigator,
      builder: (context, child) {
        // Mini lecteur Spotify accessible depuis n'importe quel écran, en haut à droite.
        final screen = Stack(
          children: [
            child!,
            Positioned(top: Td.s3, right: Td.s3, child: MusicButton(navigator: _navigator)),
          ],
        );
        return pixelAspect == 1 ? screen : _SquarePixels(child: screen);
      },
    );
  }
}

/// Dessine l'appli plus étroite en pixels pour que ses cercles restent ronds sur une dalle à pixels larges.
class _SquarePixels extends StatelessWidget {
  const _SquarePixels({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final size = Size(box.maxWidth * pixelAspect, box.maxHeight);
      return FittedBox(
        fit: BoxFit.fill,
        child: SizedBox.fromSize(
          size: size,
          child: MediaQuery(data: MediaQuery.of(context).copyWith(size: size), child: child),
        ),
      );
    },
  );
}
