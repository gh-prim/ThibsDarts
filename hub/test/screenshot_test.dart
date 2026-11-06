@Tags(['screenshot'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:dartos_hub/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _font(String family, String path) async {
  final l = FontLoader(family)..addFont(rootBundle.load(path));
  await l.load();
}

void main() {
  testWidgets('captures', (tester) async {
    final out = Platform.environment['SHOTS'];
    if (out == null) return;
    await tester.runAsync(() async {
      await _font('Inter', 'assets/fonts/Inter.ttf');
      await _font('Nunito', 'assets/fonts/Nunito.ttf');
      await _font('MaterialIcons', 'fonts/MaterialIcons-Regular.otf');
      await _font('PermanentMarker', 'assets/fonts/PermanentMarker.ttf');
      await _font('packages/lucide_icons_flutter/Lucide', 'packages/lucide_icons_flutter/assets/lucide.ttf');
    });
    tester.view.physicalSize = const Size(1024, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const DartOsApp());

    Future<void> advance(int ms) async {
      for (var t = 0; t < ms; t += 50) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> shot(String name) async {
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      final ro = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
      await tester.runAsync(() async {
        final img = await ro.toImage();
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    await advance(700);
    await shot('1-boot');
    await advance(2000);
    await advance(300);
    await shot('2-pret');
    await advance(1500);
    await advance(600);
    await shot('3-accueil');

    // Partie 501 simulée : Nouvelle partie, invité, Lancer, puis on touche le plateau.
    await tester.tap(find.text('Nouvelle partie'));
    await advance(600);
    await tester.tap(find.text('Invité'));
    await advance(200);
    await shot('3b-nouvelle-partie');
    await tester.tap(find.text('Lancer'));
    await tester.pump();
    await advance(600);
    await shot('4-debut');
    const c = Offset(480, 300);
    const k = 440 / 410;
    Offset at(double x, double y) => c + Offset(x, y) * k;
    await tester.tapAt(at(0, -135)); // S20
    await advance(2000);
    await tester.tapAt(at(0, -103)); // T20
    await advance(300);
    await shot('5a');
    await advance(600);
    await shot('5-triple');
    await advance(1200);
    await tester.tap(find.text('Hors cible'));
    await advance(600);
    await shot('6-hors-cible');
    await advance(1500);
    await shot('7-fin-de-tour');

    await tester.tap(find.text('Corriger'));
    await advance(600);
    await tester.tap(find.text('Fléchette 3'));
    await advance(200);
    await tester.tap(find.text('19').last);
    await tester.tap(find.text('Triple').last);
    await advance(300);
    await shot('8-correction');
    await tester.tap(find.text('Valider'));
    await advance(600);
    await shot('9-corrige');

    // Retour accueil puis Nouvelle partie
    await tester.longPress(find.bySemanticsLabel('ThibsDarts').first);
    await advance(600);
    await shot('10-accueil-apres');
  });
}
