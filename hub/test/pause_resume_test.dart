import 'dart:io';

import 'package:darts_engine/darts_engine.dart';
import 'package:dartos_hub/game/paused_game.dart';
import 'package:dartos_hub/game_config.dart';
import 'package:dartos_hub/screens/mode_game_screen.dart';
import 'package:dartos_hub/setup/owner_store.dart';
import 'package:dartos_hub/widgets/dartboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pause depuis la croix, puis reprise (comme après un redémarrage) : même état, la partie continue.
void main() {
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('dartos-pause');
    OwnerStore.useDirectory(dir.path);
  });

  Future<void> fonts(WidgetTester t) => t.runAsync(() async {
    for (final (f, p) in const [
      ('Inter', 'assets/fonts/Inter.ttf'),
      ('Nunito', 'assets/fonts/Nunito.ttf'),
      ('PermanentMarker', 'assets/fonts/PermanentMarker.ttf'),
      ('packages/lucide_icons_flutter/Lucide', 'packages/lucide_icons_flutter/assets/lucide.ttf'),
    ]) {
      await (FontLoader(f)..addFont(rootBundle.load(p))).load();
    }
  });

  Future<void> open(WidgetTester t, Widget Function() screen) async {
    t.view.physicalSize = const Size(1024, 600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Inter'),
        home: Builder(
          builder: (c) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => screen())),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
  }

  Future<void> dart(WidgetTester t, DartThrow d) async {
    final r = t.getRect(find.byType(Dartboard).first);
    await t.tapAt(r.center + boardPositionFor(d) * (r.width / 410));
    await t.pump(const Duration(milliseconds: 20));
  }

  Future<void> pause(WidgetTester t) async {
    final stop = find.bySemanticsLabel('Arrêter la partie');
    await t.tap(stop.evaluate().isNotEmpty ? stop.first : find.text('Arrêter'));
    await t.pumpAndSettle();
    expect(find.text('Pause ou fin de partie ?'), findsOneWidget);
    await t.tap(find.text('Pause'));
    await t.pumpAndSettle();
    expect(find.text('go'), findsOneWidget, reason: 'retour à l’accueil');
  }

  testWidgets('501 : pause puis reprise', (t) async {
    await fonts(t);
    const cfg = GameConfig(players: ['A', 'B'], startScore: 501);
    await open(t, () => gameScreenFor(cfg));
    for (final d in [const DartThrow.triple(20), const DartThrow.triple(20), const DartThrow(20)]) {
      await dart(t, d);
    }
    await t.tap(find.text('Fin de tour'));
    await t.pump(const Duration(milliseconds: 20));
    await dart(t, const DartThrow(20));
    await pause(t);

    final p = PausedGame.load();
    expect(p, isNotNull);
    expect(p!.config.startScore, 501);
    expect(p.log.where((e) => e['t'] == 'd').length, 4, reason: '${p.log}');
    expect(p.log.where((e) => e['t'] == 'e').length, 1);

    // Reprise, comme depuis l'accueil après un redémarrage.
    await t.pumpWidget(const SizedBox());
    await open(t, () => gameScreenFor(p.config, paused: p));
    expect(find.text('361'), findsWidgets, reason: 'A a déjà fait 140');
    expect(find.text('481'), findsWidgets, reason: 'B a déjà mis 20');
    expect(PausedGame.load(), isNull, reason: 'pause effacée à la reprise');
    await dart(t, const DartThrow(20));
    expect(find.text('461'), findsWidgets);
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets('Cricket Random : mêmes numéros après reprise', (t) async {
    await fonts(t);
    const cfg = GameConfig(players: ['A', 'B'], mode: GameMode.cricket, cricketVariant: CricketVariant.random);
    final log = GameLog();
    final a = CricketGame.numbersFor(CricketVariant.random, log.random);
    final b = CricketGame.numbersFor(CricketVariant.random, GameLog(seed: log.seed).random);
    expect(a, b);
    await open(t, () => gameScreenFor(cfg));
    await dart(t, const DartThrow(1));
    await pause(t);
    final p = PausedGame.load()!;
    expect(p.config.cricketVariant, CricketVariant.random);
    await t.pumpWidget(const SizedBox());
    await open(t, () => gameScreenFor(p.config, paused: p));
    expect(find.text('Fin de tour'), findsOneWidget);
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets('Volées libres : pause puis reprise', (t) async {
    await fonts(t);
    const cfg = GameConfig(players: ['A'], freeVolleys: 10, practice: true);
    await open(t, () => gameScreenFor(cfg));
    await dart(t, const DartThrow.triple(20));
    await dart(t, const DartThrow(5));
    await pause(t);
    final p = PausedGame.load()!;
    expect(p.config.freeVolleys, 10);
    await t.pumpWidget(const SizedBox());
    await open(t, () => gameScreenFor(p.config, paused: p));
    expect(find.text('65'), findsWidgets, reason: 'T20 + 5 déjà comptés');
    await t.pump(const Duration(seconds: 3));
  });
}
