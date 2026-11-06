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
    });
    tester.view.physicalSize = const Size(1024, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const DartOsApp());

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

    await tester.pump(const Duration(milliseconds: 700));
    await shot('1-boot');
    await tester.pump(const Duration(milliseconds: 2000));
    await tester.pump(const Duration(milliseconds: 300));
    await shot('2-pret');
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 600));
    await shot('3-accueil');
  });
}
