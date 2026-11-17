@Tags(['screenshot'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dartos_hub/cam/cam_link.dart';
import 'package:dartos_hub/screens/trace_screen.dart';
import 'package:dartos_hub/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _font(String family, String path) async {
  final l = FontLoader(family)..addFont(rootBundle.load(path));
  await l.load();
}

/// Captures de l'écran Caméras sur un vrai serveur du Pi 5 (TRACE_BASE, ex. http://127.0.0.1:8098).
void main() {
  testWidgets('captures écran caméras', (tester) async {
    final out = Platform.environment['SHOTS'];
    final base = Platform.environment['TRACE_BASE'];
    if (out == null || base == null) return;
    HttpOverrides.global = null;
    await tester.runAsync(() async {
      await _font('Inter', 'assets/fonts/Inter.ttf');
      await _font('Nunito', 'assets/fonts/Nunito.ttf');
      await _font('packages/lucide_icons_flutter/Lucide', 'packages/lucide_icons_flutter/assets/lucide.ttf');
    });
    tester.view.physicalSize = const Size(1024, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    CamLink.instance.camStatus.value = {'state': 'online', 'preview': base};
    final id = await tester.runAsync(() async {
      final c = HttpClient();
      final res = await (await c.getUrl(Uri.parse('$base/traces'))).close();
      final list = jsonDecode(await res.transform(utf8.decoder).join()) as List;
      return (list.first as Map)['id'] as String;
    });

    Future<void> shot(String name) async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      final ro = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
      await tester.runAsync(() async {
        final img = await ro.toImage();
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Inter', scaffoldBackgroundColor: Td.beton),
        home: RepaintBoundary(child: TraceScreen(traceId: id!)),
      ),
    );
    await shot('trace-bas');
    await tester.tap(find.text('Cible'));
    await shot('trace-cible');
    await tester.tap(find.text('Haut droite').first);
    await tester.pump();
    await tester.tap(find.text('Zoom'));
    await shot('trace-zoom');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    // Laisse se finir les requêtes HTTP en cours (délais de connexion de CamTraces).
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 7)));
    await tester.pump(const Duration(seconds: 20));
  });
}
