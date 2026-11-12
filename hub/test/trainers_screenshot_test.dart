@Tags(['screenshot'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:darts_engine/darts_engine.dart';
import 'package:dartos_hub/game_config.dart';
import 'package:dartos_hub/screens/game_screen.dart';
import 'package:dartos_hub/screens/mode_game_screen.dart';
import 'package:dartos_hub/screens/new_game_screen.dart';
import 'package:dartos_hub/screens/trainer_screen.dart';
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

void play(TurnGame g, List<List<DartThrow>> turns) {
  for (final t in turns) {
    for (final d in t) {
      if (g.awaitingNextPlayer) break;
      g.throwDart(d);
    }
    g.nextPlayer();
  }
}

const m = DartThrow.miss();
DartThrow s(int n) => DartThrow.single(n);
DartThrow d(int n) => DartThrow.double(n);
DartThrow t(int n) => DartThrow.triple(n);

void main() {
  setUpAll(() => OwnerStore.useDirectory(Directory.systemTemp.createTempSync('dartos-trainers').path));

  testWidgets('captures entraînements', (tester) async {
    final out = Platform.environment['SHOTS'];
    if (out == null) return;
    await tester.runAsync(() async {
      await _font('Inter', 'assets/fonts/Inter.ttf');
      await _font('Nunito', 'assets/fonts/Nunito.ttf');
      await _font('PermanentMarker', 'assets/fonts/PermanentMarker.ttf');
      await _font('packages/lucide_icons_flutter/Lucide', 'packages/lucide_icons_flutter/assets/lucide.ttf');
    });
    final size = Platform.environment['SMALL'] == null ? const Size(1024, 600) : const Size(800, 480);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Future<void> shot(String name, Widget w, {List<String>? taps}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Inter', scaffoldBackgroundColor: Td.beton),
          home: RepaintBoundary(
            child: KeyedSubtree(key: ValueKey(name), child: w),
          ),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      for (final tap in taps ?? const <String>[]) {
        await tester.tap(find.text(tap).first);
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
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

    Widget trainer(GameMode mode, TurnGame g, {int option = 0}) => TrainerScreen(
      config: GameConfig(players: const ['Thibs'], mode: mode, practice: true, option: option),
      game: g,
    );

    final c40 = LadderGame.catch40('Thibs');
    play(c40, [
      [t(7), d(20)],
      [s(2), d(30 ~/ 1 > 20 ? 15 : 15), m],
      [s(3), d(16), m],
      [m, m, m],
      [m, m, m],
    ]);
    c40.throwDart(s(1));
    await shot('t-catch40', trainer(GameMode.catch40, c40));

    final f41 = LadderGame.fortyOne('Thibs');
    play(f41, [
      [s(1), d(20)],
      [m, m, m],
      [s(3), d(20)],
    ]);
    await shot('t-41', trainer(GameMode.fortyOne, f41));

    final nine = CheckoutDrill.nineDarts('Thibs');
    play(nine, [
      [t(20), s(20), s(1)],
      [d(20)],
      [t(20), t(19), m],
    ]);
    nine.throwDart(s(1));
    await shot('t-ninedarts', trainer(GameMode.nineDarts, nine, option: 121));

    final ton = CheckoutDrill.ton70('Thibs');
    play(ton, [
      [t(20), t(20)],
    ]);
    await shot('t-170', trainer(GameMode.ton70, ton));

    final rnd = CheckoutDrill.random('Thibs', range: CheckoutRange.medium);
    play(rnd, [
      [m, m, m],
    ]);
    await shot('t-random', trainer(GameMode.randomCheckout, rnd, option: 1));

    final jdc = JdcGame('Thibs');
    play(jdc, [
      [s(10), d(10), t(10)],
      [s(11), m, m],
      [t(12), m, m],
    ]);
    jdc.throwDart(s(13));
    await shot('t-jdc', trainer(GameMode.jdc, jdc));
    final jdc2 = JdcGame('Thibs');
    for (var i = 0; i < 7; i++) {
      play(jdc2, [
        [m, m, m],
      ]);
    }
    jdc2.throwDart(d(4));
    await shot('t-jdc-doubles', trainer(GameMode.jdc, jdc2));

    final n99 = Darts99Game('Thibs');
    play(n99, [
      [t(20), s(20), s(1)],
      [s(20), s(20), d(20)],
      [s(5), s(20), m],
    ]);
    await shot('t-99', trainer(GameMode.darts99, n99, option: 20));

    final rtw = RoundTheWorldGame('Thibs');
    play(rtw, [
      [s(1), d(1), m],
      [m, m, m],
      [t(3), s(3), m],
    ]);
    rtw.throwDart(s(4));
    await shot('t-rtw', trainer(GameMode.roundTheWorld, rtw, option: 1));

    final cu = VolleyGame('Thibs', volleys: 8);
    play(cu, [
      [t(20), s(20), s(1)],
      [s(20), s(5), s(20)],
      [t(20), t(20), s(20)],
    ]);
    cu.throwDart(s(20));
    await shot('t-countup', trainer(GameMode.countUp, cu, option: 8));

    final ccu = CricketCountUpGame('Thibs');
    play(ccu, [
      [t(20), s(19), s(1)],
      [d(18), s(17), DartThrow.bull],
    ]);
    ccu.throwDart(t(16));
    await shot('t-cricketcountup', trainer(GameMode.cricketCountUp, ccu));

    // Fin d'entraînement
    final end = VolleyGame('Thibs', volleys: 1);
    play(end, [
      [t(20), t(20), s(20)],
    ]);
    await shot('t-fin', trainer(GameMode.countUp, end, option: 1));

    // Choix de l'entraînement
    await shot('choix-finir', const NewGameScreen(practice: true));
    await shot('choix-viser', const NewGameScreen(practice: true), taps: ['Viser']);
    await shot('choix-scorer', const NewGameScreen(practice: true), taps: ['Scorer', 'Volées libres']);
    await shot('choix-robot', const NewGameScreen(practice: true), taps: ['Robot']);
    await shot('choix-serie', const NewGameScreen(practice: true), taps: ['Viser', 'Série sur cible']);
    await shot('soiree', const NewGameScreen(), taps: ['Gotcha']);
    await shot('soiree-cricket', const NewGameScreen(), taps: ['Cricket', 'Tactic']);

    // Soirée
    final names = ['Thibs', 'Max', 'Inès'];
    final ber = HalveItGame.bermuda(names);
    play(ber, [
      [s(12), s(12), m],
      [m, m, m],
      [t(12), m, m],
    ]);
    await shot(
      'mode-bermuda',
      ModeGameScreen(
        config: GameConfig(players: names, mode: GameMode.bermuda),
        game: ber,
      ),
    );
    final got = GotchaGame(names);
    play(got, [
      [t(20), m, m],
      [t(20), t(20), m],
    ]);
    got.throwDart(t(20));
    await shot(
      'mode-gotcha',
      ModeGameScreen(
        config: GameConfig(players: names, mode: GameMode.gotcha),
        game: got,
      ),
    );

    final tac = CricketGame(['Thibs', 'Max'], variant: CricketVariant.tactic);
    play(tac, [
      [t(20), t(11), s(10)],
    ]);
    await shot(
      'mode-cricket-tactic',
      ModeGameScreen(
        config: GameConfig(
          players: const ['Thibs', 'Max'],
          mode: GameMode.cricket,
          cricketVariant: CricketVariant.tactic,
        ),
        game: tac,
      ),
    );

    // Robot
    await shot(
      'bot-501',
      const GameScreen(config: GameConfig(players: ['Thibs', GameConfig.botName], botLevel: 60, practice: true)),
      taps: [],
    );
  });
}
