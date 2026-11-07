@Tags(['screenshot'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:dartos_hub/game_config.dart';
import 'package:dartos_hub/screens/tournament_screen.dart';
import 'package:dartos_hub/setup/owner_store.dart';
import 'package:dartos_hub/theme/tokens.dart';
import 'package:dartos_hub/tournament/tournament.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _font(String family, String path) async {
  final l = FontLoader(family)..addFont(rootBundle.load(path));
  await l.load();
}

void main() {
  testWidgets('captures tournoi', (tester) async {
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
    OwnerStore.useDirectory(Directory.systemTemp.createTempSync('dartos-tshot').path);
    AppState.setOwner(const Owner(firstName: 'Thibault', lastName: '', nickname: 'Thibs'));

    final names = ['Thibs', 'Max', 'Inès', 'Léo', 'Hugo', 'Paul', 'Sarah', 'Emma', 'Camille', 'Julie', 'Tom', 'Nico', 'Lucas', 'Chloé'];
    final t = Tournament(id: 't', organizer: 'owner', mode: '501', legsToWin: 3, createdAt: DateTime(2026));
    for (final (i, n) in names.indexed) {
      t.guests['g$i'] = n;
      t.entrants.add('g$i');
    }
    t.draw(Random(3));
    t.state = 'en_cours';
    for (var i = 0; i < 9; i++) {
      t.record(t.next!.id, 3, i % 3);
    }
    await tester.runAsync(() => TournamentStore.instance.set(t));
    final json = Platform.environment['TOURNOI_JSON'];
    if (json != null) File(json).writeAsStringSync(jsonEncode({'tournament': TournamentStore.instance.public()}));

    Future<void> shot(String name, Widget w) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Inter', scaffoldBackgroundColor: Td.beton),
          home: RepaintBoundary(child: w),
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
    }

    await shot('tournoi-match', TournamentMatchView(tournament: t, match: t.next!, onLaunch: () {}));
    await shot('tournoi-tableau', const TournamentBracketScreen());
    await shot('tournoi-vainqueur', TournamentChampionView(champion: 'Thibs', onDone: () {}));
  });
}
