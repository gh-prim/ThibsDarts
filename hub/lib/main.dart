import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'cam/cam_link.dart';
import 'cam/cam_pairing.dart';
import 'screens/boot_screen.dart';
import 'screens/debug_screen.dart';
import 'system/system_update.dart';
import 'theme/tokens.dart';

void main() {
  CamLink.instance.start();
  CamPairing.instance.start();
  SystemUpdate.start();
  runApp(const DartOsApp());
}

/// Largeur d'un pixel de l'écran rapportée à sa hauteur. Les petites dalles 1024x600 (7")
/// ont des pixels un peu plus larges que hauts : sans correction, la cible sort ovale.
/// Réglé par DARTOS_PIXEL_ASPECT dans le service du Pi (ex. 1.05), 1 par défaut.
/// Appliqué seulement sur une dalle 1024x600 : les écrans 10" ont des pixels carrés.
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
      builder: (context, child) => ScreenFit(
        // Mode Debug : pastille Signaler par-dessus tous les écrans.
        child: Stack(
          children: [
            child!,
            const Positioned(left: 8, bottom: 8, child: DebugBadge()),
            const Positioned.fill(child: SystemUpdateOverlay()),
          ],
        ),
      ),
    );
  }
}

/// Taille de référence de toute l'interface : la dalle 7" 1024x600 des planches de design.
const designSize = Size(1024, 600);

/// Mise à l'échelle de l'interface selon la résolution réelle de l'écran, lue au démarrage.
/// Le côté limitant (largeur ou hauteur) est ramené à la planche 1024x600, l'autre côté gagne
/// un peu de place : 1280x800 (10") donne 1024x640, 1920x1080 donne 1067x600, 1920x1200 donne
/// 1024x640. Tout (textes, graphiques, cible, cibles tactiles) grandit du même facteur.
class ScreenFit extends StatelessWidget {
  const ScreenFit({super.key, required this.child, this.aspect});

  final Widget child;

  /// Forme d'un pixel (tests) ; par défaut [pixelAspect] sur une dalle 1024x600, 1 ailleurs.
  final double? aspect;

  /// Taille logique de l'interface et facteur d'agrandissement pour un écran de [physical] pixels.
  static ({Size size, double scale}) layout(Size physical, double aspect) {
    final w = physical.width * aspect; // en pixels carrés
    final h = physical.height;
    final scale = math.min(w / designSize.width, h / designSize.height);
    return (size: Size(w / scale, h / scale), scale: scale);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final physical = mq.size * mq.devicePixelRatio;
    if (physical.isEmpty) return child;
    final is7 = physical.width.round() == 1024 && physical.height.round() == 600;
    final fit = layout(physical, aspect ?? (is7 ? pixelAspect : 1));
    return FittedBox(
      fit: BoxFit.fill,
      child: SizedBox.fromSize(
        size: fit.size,
        child: MediaQuery(
          data: mq.copyWith(
            size: fit.size,
            devicePixelRatio: fit.scale,
            padding: mq.padding / fit.scale * mq.devicePixelRatio,
            viewPadding: mq.viewPadding / fit.scale * mq.devicePixelRatio,
            viewInsets: mq.viewInsets / fit.scale * mq.devicePixelRatio,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Plein écran pendant la mise à jour du système (le Pi redémarre à la fin).
class SystemUpdateOverlay extends StatelessWidget {
  const SystemUpdateOverlay({super.key});

  static const _steps = {
    'system': 'Installation du système…',
    'packages': 'Installation des paquets…',
    'reboot': 'Le Pi 4 redémarre…',
  };

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: SystemUpdate.step,
    builder: (context, step, _) => step == null
        ? const SizedBox.shrink()
        : ColoredBox(
            color: Td.betonNuit,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: Td.s4,
                children: [
                  const Icon(LucideIcons.refreshCw, size: 56, color: Td.sunset),
                  Text('Mise à jour du système', style: TdText.title),
                  Text(_steps[step]!, style: TdText.body),
                ],
              ),
            ),
          ),
  );
}
