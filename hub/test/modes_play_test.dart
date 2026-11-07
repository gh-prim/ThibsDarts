import 'dart:io';

import 'package:darts_engine/darts_engine.dart';
import 'package:dartos_hub/game_config.dart';
import 'package:dartos_hub/setup/owner_store.dart';
import 'package:dartos_hub/screens/mode_game_screen.dart';
import 'package:dartos_hub/widgets/dartboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Joue des parties entières sur le vrai écran de jeu, en touchant le plateau.
void main() {
  setUpAll(() => OwnerStore.useDirectory(Directory.systemTemp.createTempSync('dartos-modes').path));

  const m = DartThrow.miss();

  Future<void> open(WidgetTester t, GameMode mode, {TurnGame? game, List<String> players = const ['A', 'B']}) async {
    await t.runAsync(() async {
      for (final (f, p) in const [
        ('Inter', 'assets/fonts/Inter.ttf'),
        ('Nunito', 'assets/fonts/Nunito.ttf'),
        ('PermanentMarker', 'assets/fonts/PermanentMarker.ttf'),
        ('packages/lucide_icons_flutter/Lucide', 'packages/lucide_icons_flutter/assets/lucide.ttf'),
      ]) {
        await (FontLoader(f)..addFont(rootBundle.load(p))).load();
      }
    });
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
                onPressed: () => Navigator.of(c).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ModeGameScreen(
                      config: GameConfig(players: players, mode: mode),
                      game: game,
                    ),
                  ),
                ),
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
    if (d.isMiss) {
      await t.tap(find.text('Hors cible'));
    } else {
      final r = t.getRect(find.byType(Dartboard).first);
      await t.tapAt(r.center + boardPositionFor(d) * (r.width / 410));
    }
    await t.pump(const Duration(milliseconds: 20));
  }

  Future<void> turn(WidgetTester t, List<DartThrow> darts) async {
    for (final d in darts) {
      await dart(t, d);
    }
    await t.tap(find.text('Fin de tour'));
    await t.pump(const Duration(milliseconds: 20));
  }

  Future<void> expectWinner(WidgetTester t, String name) async {
    await t.pump(const Duration(seconds: 2));
    expect(find.text('Rejouer'), findsOneWidget, reason: 'écran de victoire');
    expect(find.textContaining('$name plie la partie'), findsOneWidget);
    // Revanche : on repart de zéro.
    await t.tap(find.text('Rejouer'));
    await t.pump(const Duration(seconds: 2));
    expect(find.text('Rejouer'), findsNothing);
    expect(find.text('Fin de tour'), findsOneWidget);
    // Accueil.
    await t.pump(const Duration(seconds: 3));
  }

  testWidgets('Cricket : A ferme tout et gagne', (t) async {
    await open(t, GameMode.cricket);
    await turn(t, [const DartThrow.triple(20), const DartThrow.triple(19), const DartThrow.triple(18)]);
    expect(find.text('Cricket · Tour 1'), findsOneWidget);
    await turn(t, [m, m, m]);
    expect(find.text('Cricket · Tour 2'), findsOneWidget);
    await turn(t, [const DartThrow.triple(17), const DartThrow.triple(16), const DartThrow.triple(15)]);
    await turn(t, [const DartThrow(20), m, m]);
    await dart(t, DartThrow.bull);
    await dart(t, DartThrow.outerBull);
    expect(find.text('Terminer'), findsOneWidget);
    await expectWinner(t, 'A');
  });

  testWidgets('Around the clock : A fait le tour', (t) async {
    await open(t, GameMode.clock);
    var n = 1;
    while (n <= 20) {
      final darts = [for (var i = 0; i < 3 && n <= 20; i++) DartThrow(n++)];
      if (n > 20) {
        for (final d in darts) {
          await dart(t, d);
        }
        break;
      }
      await turn(t, darts);
      expect(find.text('B, vise le'), findsOneWidget);
      await turn(t, [const DartThrow(2), m, m]);
    }
    await expectWinner(t, 'A');
  });

  testWidgets('Shanghai : S, D, T du 1 au premier tour', (t) async {
    await open(t, GameMode.shanghai);
    expect(find.text('Shanghai · Manche 1'), findsOneWidget);
    await dart(t, const DartThrow(1));
    await dart(t, const DartThrow.double(1));
    await dart(t, const DartThrow.triple(1));
    await expectWinner(t, 'A');
  });

  testWidgets('Shanghai : 7 manches aux points', (t) async {
    await open(t, GameMode.shanghai);
    for (var r = 1; r <= 7; r++) {
      expect(find.text('Shanghai · Manche $r'), findsOneWidget);
      await turn(t, [m, m, m]);
      await turn(t, [DartThrow(r), m, m]);
    }
    await expectWinner(t, 'B');
  });

  testWidgets('Killer : A devient killer et élimine B', (t) async {
    await open(t, GameMode.killer, game: KillerGame(['A', 'B'], numbers: [20, 6]));
    await turn(t, [const DartThrow.double(20), const DartThrow.double(6), const DartThrow.double(6)]);
    expect(find.text('B perd une vie. Plus que 1.'), findsOneWidget);
    await turn(t, [const DartThrow.double(20), m, m]);
    await dart(t, const DartThrow.double(6));
    await expectWinner(t, 'A');
  });

  testWidgets('Halve-it : 9 manches, B rate tout', (t) async {
    await open(t, GameMode.halveIt);
    const hits = [
      DartThrow(19),
      DartThrow(18),
      DartThrow(17),
      DartThrow.double(20),
      DartThrow(16),
      DartThrow.triple(20),
      DartThrow(15),
      DartThrow(20),
      DartThrow.outerBull,
    ];
    for (final h in hits) {
      await turn(t, [h, m, m]);
      await turn(t, [m, m, m]);
    }
    await expectWinner(t, 'A');
  });

  testWidgets("Bob's 27 : B tombe sous zéro", (t) async {
    await open(t, GameMode.bobs27);
    for (var r = 1; r <= 5; r++) {
      expect(find.text("Bob's 27 · D$r"), findsOneWidget);
      await turn(t, [DartThrow.double(r), m, m]);
      if (r < 5) await turn(t, [m, m, m]);
    }
    // 27 - 2 - 4 - 6 - 8 - 10 = -3 : B éliminé au 5e tour.
    await dart(t, m);
    await dart(t, m);
    await dart(t, m);
    expect(find.text('Terminer'), findsOneWidget);
    await expectWinner(t, 'A');
  });

  testWidgets('Halve-it : égalité si tout le monde rate', (t) async {
    await open(t, GameMode.halveIt);
    for (var r = 0; r < 9; r++) {
      await turn(t, [m, m, m]);
      await turn(t, [m, m, m]);
    }
    await t.pump(const Duration(seconds: 2));
    expect(find.textContaining('A et B à égalité'), findsOneWidget);
    await t.tap(find.text('Rejouer'));
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets("Bob's 27 en solo : sous zéro, pas de victoire", (t) async {
    await open(t, GameMode.bobs27, players: const ['A']);
    for (var r = 1; r <= 4; r++) {
      await turn(t, [m, m, m]);
    }
    await dart(t, m);
    await dart(t, m);
    await dart(t, m);
    await t.pump(const Duration(seconds: 2));
    expect(find.textContaining('Sous zéro au D5'), findsOneWidget);
    expect(find.textContaining('plie la partie'), findsNothing);
    await t.tap(find.text('Rejouer'));
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets('Killer à 3 : un éliminé est sauté', (t) async {
    await open(
      t,
      GameMode.killer,
      game: KillerGame(['A', 'B', 'C'], numbers: [20, 6, 3], lives: 1),
      players: const ['A', 'B', 'C'],
    );
    await turn(t, [const DartThrow.double(20), const DartThrow.double(6), m]);
    expect(find.text('B est éliminé.'), findsOneWidget);
    expect(find.text('C, ton numéro: 3'), findsOneWidget);
    await turn(t, [m, m, m]);
    expect(find.text('A, ton numéro: 20'), findsOneWidget);
    await dart(t, const DartThrow.double(3));
    await expectWinner(t, 'A');
  });
}
