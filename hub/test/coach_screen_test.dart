import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:darts_engine/darts_engine.dart';
import 'package:dartos_hub/coach/coach_store.dart';
import 'package:dartos_hub/game_config.dart';
import 'package:dartos_hub/history/history_store.dart';
import 'package:dartos_hub/screens/coach_screen.dart';
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

/// Milieu du double [s], décalé de [deg] degrés.
Map<String, Object?> shot(String aim, String d, int sector, double deg, {double dr = 0}) {
  final a = (sectors.indexOf(sector) * 18 + deg) * math.pi / 180;
  return {
    'a': aim,
    'd': d,
    'x': (166 + dr) * math.sin(a),
    'y': -(166 + dr) * math.cos(a),
    'z': 1,
    'ok': d == aim,
    'st': 0,
  };
}

void main() {
  setUpAll(() async {
    OwnerStore.useDirectory(Directory.systemTemp.createTempSync('dartos-coach').path);
    AppState.owner = 'Thibs';
    // Une séance passée : D16 raté à gauche, D20 bien.
    await HistoryStore.instance.add({
      'id': '1',
      'at': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
      'mode': 'Coach',
      'kind': 'coach',
      'training': true,
      'players': [
        {
          'id': 'owner',
          'name': 'Thibs',
          'darts': 30,
          'score': 40,
          'shots': [
            for (var i = 0; i < 12; i++) shot('D16', i % 4 == 0 ? 'D16' : 'S16', 16, -6, dr: i % 4 == 0 ? 0 : -9),
            for (var i = 0; i < 18; i++) shot('D20', i % 2 == 0 ? 'D20' : 'S20', 20, 1, dr: i % 2 == 0 ? 0 : -8),
          ],
          'checkouts': [
            {'s': 32, 'ok': false},
            {'s': 32, 'ok': false},
          ],
          'levels': {
            'zones': {'D20': 1.5},
            'checkout': 1.2,
            'pressure': 0,
          },
        },
      ],
    });
  });

  test('profil lu dans l’historique', () {
    final c = CoachStore.of('owner');
    final p = c.profile;
    expect(p.skills['D16']!.attempts, 12);
    expect(p.skills['D16']!.tangential, lessThan(0));
    expect(p.missed[32], 2);
    expect(p.levels.checkout, 1.2);
    expect(c.toJson()['weakest'], isA<List<Object?>>());
  });

  testWidgets('séance complète à la main, puis enregistrée', (tester) async {
    final out = Platform.environment['SHOTS'];
    {
      await tester.runAsync(() async {
        await _font('Inter', 'assets/fonts/Inter.ttf');
        await _font('Nunito', 'assets/fonts/Nunito.ttf');
        await _font('PermanentMarker', 'assets/fonts/PermanentMarker.ttf');
        await _font('packages/lucide_icons_flutter/Lucide', 'packages/lucide_icons_flutter/assets/lucide.ttf');
      });
    }
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
          child: CoachScreen(
            config: GameConfig(players: ['Thibs'], mode: GameMode.coach, practice: true),
          ),
        ),
      ),
    );
    await pumpABit(10);
    await capture('coach-carte');

    await tester.tap(find.text('Commencer'));
    await pumpABit();

    Future<void> tapDart(DartThrow d) async {
      final box = tester.getRect(find.byType(Dartboard));
      final scale = box.width / 410;
      final p = boardPositionFor(d);
      await tester.tapAt(box.center + p * scale);
      await pumpABit(2);
    }

    var volleys = 0, shotDone = <String>{};
    final rnd = math.Random(3);
    while (find.text('SÉANCE FINIE').evaluate().isEmpty && volleys < 120) {
      for (var i = 0; i < 3; i++) {
        final board = tester.widget<Dartboard>(find.byType(Dartboard));
        if (board.aimed == null) break;
        final aim = board.aimed!;
        // 2 sur 3 dans la case visée, sinon le simple à côté.
        await tapDart(rnd.nextInt(3) < 2 ? aim : DartThrow.single(aim.sector == 25 ? 20 : aim.sector));
        if (board.zone < 1 && !shotDone.contains('zone')) {
          shotDone.add('zone');
          await capture('coach-doubles');
        }
      }
      final sub = find.textContaining('Fantôme');
      if (sub.evaluate().isNotEmpty && !shotDone.contains('pression')) {
        shotDone.add('pression');
        await capture('coach-pression');
      }
      if (find.textContaining('Finis le').evaluate().isNotEmpty && !shotDone.contains('sorties')) {
        shotDone.add('sorties');
        await capture('coach-sorties');
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
    await capture('coach-fin');

    await tester.tap(find.text('Terminer').last);
    await pumpABit(10);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));

    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    final saved = HistoryStore.instance.all().where((m) => m['kind'] == 'coach').toList();
    expect(saved.length, 2);
    final p = (saved.first['players'] as List).first as Map;
    expect((p['shots'] as List).isNotEmpty, isTrue);
    expect(p['levels'], isA<Map<Object?, Object?>>());
  });
}
