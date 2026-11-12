import 'dart:io';
import 'dart:ui' as ui;

import 'package:dartos_hub/game_config.dart';
import 'package:dartos_hub/screens/training_screen.dart';
import 'package:dartos_hub/setup/owner_store.dart';
import 'package:dartos_hub/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _font(String family, String path) async {
  final l = FontLoader(family)..addFont(rootBundle.load(path));
  await l.load();
}

void main() {
  setUpAll(() => OwnerStore.useDirectory(Directory.systemTemp.createTempSync('dartos-training').path));

  testWidgets('volées libres : hors cible et corriger', (tester) async {
    tester.view.physicalSize = const Size(1024, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final out = Platform.environment['SHOTS'];
    if (out != null) {
      await tester.runAsync(() async {
        await _font('Inter', 'assets/fonts/Inter.ttf');
        await _font('Nunito', 'assets/fonts/Nunito.ttf');
        await _font('packages/lucide_icons_flutter/Lucide', 'packages/lucide_icons_flutter/assets/lucide.ttf');
      });
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Inter', scaffoldBackgroundColor: Td.beton),
        home: const RepaintBoundary(
          child: TrainingScreen(config: GameConfig(players: ['Thibs'], freeVolleys: 0)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);

    // Une fléchette hors cible : la volée vaut 0.
    await tester.tap(find.text('Hors cible'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Cette volée'), findsOneWidget);

    // On la corrige en simple 20.
    await tester.tap(find.text('Corriger'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Corriger une fléchette'), findsOneWidget);
    await tester.tap(find.text('20').last);
    await tester.pump();
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Corriger une fléchette'), findsNothing);
    expect(find.text('S20'), findsWidgets);

    if (out != null) {
      final ro = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
      await tester.runAsync(() async {
        final img = await ro.toImage();
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$out/volees-correction.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}
