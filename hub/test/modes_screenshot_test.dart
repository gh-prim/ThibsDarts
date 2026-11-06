@Tags(['screenshot'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:darts_engine/darts_engine.dart';
import 'package:dartos_hub/game_config.dart';
import 'package:dartos_hub/screens/mode_game_screen.dart';
import 'package:dartos_hub/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _font(String family, String path) async {
  final l = FontLoader(family)..addFont(rootBundle.load(path));
  await l.load();
}

void play(TurnGame g, List<List<DartThrow>> turns) {
  for (final t in turns) {
    for (final d in t) {
      g.throwDart(d);
    }
    g.nextPlayer();
  }
}

const m = DartThrow.miss();

void main() {
  testWidgets('captures modes', (tester) async {
    final out = Platform.environment['SHOTS'];
    if (out == null) return;
    await tester.runAsync(() async {
      await _font('Inter', 'assets/fonts/Inter.ttf');
      await _font('Nunito', 'assets/fonts/Nunito.ttf');
      await _font('PermanentMarker', 'assets/fonts/PermanentMarker.ttf');
      await _font('packages/lucide_icons_flutter/Lucide', 'packages/lucide_icons_flutter/assets/lucide.ttf');
    });
    tester.view.physicalSize = const Size(1024, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Future<void> shot(String name, GameMode mode, TurnGame g) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Inter', scaffoldBackgroundColor: Td.beton),
          home: RepaintBoundary(
            child: ModeGameScreen(
              key: ValueKey(name),
              config: GameConfig(players: g.names, mode: mode),
              game: g,
            ),
          ),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final ro = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
      await tester.runAsync(() async {
        final img = await ro.toImage();
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    }

    final names = ['Thibs', 'Max', 'Inès'];
    final cricket = CricketGame(['Thibs', 'Max']);
    play(cricket, [
      [const DartThrow.triple(20), const DartThrow.triple(19), const DartThrow(18)],
      [const DartThrow.triple(20), const DartThrow(19), m],
    ]);
    cricket.throwDart(const DartThrow.triple(19));
    await shot('mode-cricket', GameMode.cricket, cricket);

    final clock = ClockGame(names);
    play(clock, [
      [const DartThrow(1), const DartThrow(2), const DartThrow(3)],
      [const DartThrow(1), const DartThrow(2), m],
      [const DartThrow(1), m, m],
      [const DartThrow(4), const DartThrow(5), const DartThrow.double(6)],
    ]);
    await shot('mode-clock', GameMode.clock, clock);

    final sh = ShanghaiGame(names);
    play(sh, [
      [const DartThrow(1), m, m],
      [const DartThrow.double(1), m, m],
      [m, m, m],
    ]);
    sh
      ..throwDart(const DartThrow(2))
      ..throwDart(const DartThrow.double(2));
    await shot('mode-shanghai', GameMode.shanghai, sh);

    final k = KillerGame(['Thibs', 'Max', 'Inès', 'Léo'], numbers: [20, 6, 11, 3]);
    play(k, [
      [const DartThrow.double(20), m, m],
      [const DartThrow.double(6), m, m],
      [m, m, m],
      [m, m, m],
    ]);
    k.throwDart(const DartThrow.double(6));
    await shot('mode-killer', GameMode.killer, k);

    final h = HalveItGame(names);
    play(h, [
      [const DartThrow(19), const DartThrow(19), m],
      [m, m, m],
      [const DartThrow.triple(19), m, m],
    ]);
    h.throwDart(const DartThrow(7));
    await shot('mode-halveit', GameMode.halveIt, h);

    final b = Bobs27Game(['Thibs', 'Max']);
    play(b, [
      [const DartThrow.double(1), m, m],
      [m, m, m],
    ]);
    b.throwDart(const DartThrow.double(2));
    await shot('mode-bobs27', GameMode.bobs27, b);
  });
}
