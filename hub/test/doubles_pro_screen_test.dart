import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:darts_engine/darts_engine.dart';
import 'package:dartos_hub/coach/coach_store.dart';
import 'package:dartos_hub/game_config.dart';
import 'package:dartos_hub/history/history_store.dart';
import 'package:dartos_hub/screens/doubles_pro_screen.dart';
import 'package:dartos_hub/setup/owner_store.dart';
import 'package:dartos_hub/theme/tokens.dart';
import 'package:dartos_hub/widgets/dartboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _font(String family, String path) async {
  final l = FontLoader(family)..addFont(rootBundle.load(path));
  await l.load();
}

void main() {
  setUpAll(() {
    OwnerStore.useDirectory(Directory.systemTemp.createTempSync('dartos-dp').path);
    AppState.owner = 'Thibs';
  });

  testWidgets('séance Doubles Pro complète à la main, puis enregistrée', (tester) async {
    final out = Platform.environment['SHOTS'];
    await tester.runAsync(() async {
      await _font('Inter', 'assets/fonts/Inter.ttf');
      await _font('Nunito', 'assets/fonts/Nunito.ttf');
      await _font('PermanentMarker', 'assets/fonts/PermanentMarker.ttf');
      await _font('packages/lucide_icons_flutter/Lucide', 'packages/lucide_icons_flutter/assets/lucide.ttf');
    });
    tester.view.physicalSize = const Size(1024, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Future<void> pumpABit([int n = 6]) async {
      for (var i = 0; i < n; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> capture(String name) async {
      if (out == null) return;
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
        home: const RepaintBoundary(
          child: DoublesProScreen(
            config: GameConfig(players: ['Thibs'], mode: GameMode.doublesPro, practice: true),
          ),
        ),
      ),
    );
    await pumpABit(10);
    await capture('dp-accueil');

    await tester.tap(find.text('Lancer'));
    await pumpABit();

    Future<void> tapDart(DartThrow d) async {
      final box = tester.getRect(find.byType(Dartboard));
      final scale = box.width / 410;
      await tester.tapAt(box.center + boardPositionFor(d) * scale);
      await pumpABit(2);
    }

    final rnd = math.Random(5);
    final shots = <String>{};
    var volleys = 0;
    while (find.text('SÉANCE FINIE').evaluate().isEmpty && volleys < 120) {
      for (var i = 0; i < 3; i++) {
        if (find.text('Bilan').evaluate().isNotEmpty) break;
        if (find.byType(Dartboard).evaluate().isEmpty) {
          // Diagnostic : le zoom, au centre du double ou 6 mm plus haut.
          final c = tester.getRect(find.text('Centre du double'));
          await tester.tapAt(Offset(c.right + 200, c.center.dy - (rnd.nextInt(3) == 0 ? 60 : 0)));
          await pumpABit(2);
          continue;
        }
        final board = tester.widget<Dartboard>(find.byType(Dartboard));
        final aim = board.aimed;
        if (aim == null) break;
        await tapDart(rnd.nextInt(3) < 2 ? aim : DartThrow.single(aim.sector == 25 ? 20 : aim.sector));
      }
      final title = find.textContaining('Bloc ').evaluate();
      if (title.isNotEmpty) {
        final t = (title.first.widget as Text).data!;
        final key = t.split('·').last.trim();
        if (shots.add(key)) await capture('dp-${shots.length}');
      }
      if (find.text('Volée suivante').evaluate().isEmpty) break;
      await tester.tap(find.text('Volée suivante'));
      await pumpABit();
      volleys++;
    }
    await tester.pump(const Duration(seconds: 2));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('SÉANCE FINIE'), findsWidgets);
    await capture('dp-fin');

    await tester.tap(find.text('Terminer').last);
    await pumpABit(10);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    final saved = HistoryStore.instance.all().where((m) => m['kind'] == 'doublesPro').toList();
    expect(saved.length, 1);
    final p = (saved.first['players'] as List).first as Map;
    expect((p['shots'] as List).isNotEmpty, isTrue);
    expect((p['blocks'] as Map).length, 4);
    expect((p['diagnostic'] as Map)['D16'], isA<Map<Object?, Object?>>());

    // Le coach apprend aussi des fléchettes de Doubles Pro.
    expect(CoachStore.of('owner').profile.skills['D16']!.attempts, greaterThan(0));
    expect(DoublesProStore('Thibs').lastOf(DpBlock.ladder), isNotNull);
  });
}
