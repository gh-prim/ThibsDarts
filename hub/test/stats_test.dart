import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dartos_hub/screens/stats_screen.dart';
import 'package:dartos_hub/stats/owner_stats.dart';
import 'package:dartos_hub/theme/tokens.dart';
import 'package:dartos_hub/widgets/dartboard.dart';
import 'package:darts_engine/darts_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 11, 9, 22, 30);

/// Trois mois d'historique inventé, au format de history.jsonl.
List<Map<String, Object?>> fakeHistory() {
  final rng = math.Random(7);
  final out = <Map<String, Object?>>[];
  const rivals = [('p-max', 'Max'), ('p-ines', 'Inès'), ('p-leo', 'Léo'), ('guest:Paul', 'Paul')];
  for (var day = 95; day >= 0; day--) {
    if (rng.nextDouble() < 0.45) continue;
    final base = now.subtract(Duration(days: day));
    var at = DateTime(base.year, base.month, base.day, 20 + rng.nextInt(3), rng.nextInt(60));
    final skill = 0.25 + (95 - day) / 95 * 0.2;
    // Un 501 contre un pote.
    final rival = rivals[rng.nextInt(rivals.length)];
    final leg = _leg(rng, skill);
    final won = rng.nextDouble() < (rival.$2 == 'Max' ? 0.3 : 0.65);
    out.add({
      'id': '${at.millisecondsSinceEpoch}',
      'at': at.toIso8601String(),
      'mode': '501',
      'kind': 'x01',
      'doubleOut': true,
      'legsToWin': 1,
      'winner': won ? 'Thibs' : rival.$2,
      'players': [
        {'id': 'owner', 'name': 'Thibs', 'won': won, 'legs': won ? 1 : 0, ...leg},
        {'id': rival.$1, 'name': rival.$2, 'won': !won, 'darts': 30},
      ],
    });
    at = at.add(const Duration(minutes: 25));
    if (rng.nextBool()) {
      final r2 = rivals[rng.nextInt(3)];
      final w2 = rng.nextDouble() < (r2.$2 == 'Max' ? 0.2 : 0.7);
      out.add({
        'id': '${at.millisecondsSinceEpoch}',
        'at': at.toIso8601String(),
        'mode': 'Cricket',
        'kind': 'cricket',
        'winner': w2 ? 'Thibs' : r2.$2,
        'players': [
          {'id': 'owner', 'name': 'Thibs', 'won': w2, 'darts': 45, 'score': 2, 'value': 1.8, 'valueLabel': 'moy.'},
          {'id': r2.$1, 'name': r2.$2, 'won': !w2, 'darts': 45},
        ],
      });
      at = at.add(const Duration(minutes: 20));
    }
    // Une série sur cible.
    final target = const ['T20', 'T20', 'T19', 'D16', 'D20', 'BULL'][rng.nextInt(6)];
    final t = TrainingTarget.fromKey(target)!;
    final throws = <Map<String, Object?>>[];
    var hits = 0;
    for (var i = 0; i < 15; i++) {
      final r = rng.nextDouble();
      final DartThrow d;
      if (t.sector == 25) {
        d = r < 0.2 ? DartThrow.outerBull : DartThrow(const [20, 1, 18, 6, 3, 19][rng.nextInt(6)]);
      } else if (r < skill) {
        d = DartThrow(t.sector, t.multiplier);
      } else if (r < 0.62) {
        d = DartThrow(t.sector);
      } else if (r < 0.85) {
        d = DartThrow(t.sector == 20 ? 5 : 7);
      } else if (r < 0.95) {
        d = DartThrow(t.sector == 20 ? 1 : 16);
      } else {
        d = const DartThrow.miss();
      }
      if (t.matches(d)) hits++;
      final p = boardPositionFor(d);
      throws.add({'d': d.label, 'x': p.dx + rng.nextDouble() * 6 - 3, 'y': p.dy + rng.nextDouble() * 6 - 3});
    }
    out.add({
      'id': '${at.millisecondsSinceEpoch}',
      'at': at.toIso8601String(),
      'mode': 'Série ${t.label}',
      'kind': 'training',
      'drill': 'target',
      'target': target,
      'length': 15,
      'winner': null,
      'players': [
        {'id': 'owner', 'name': 'Thibs', 'won': false, 'darts': 15, 'score': hits, 'throws': throws},
      ],
    });
    if (rng.nextDouble() < 0.4) {
      at = at.add(const Duration(minutes: 10));
      final scores = [for (var i = 0; i < 10; i++) 25 + rng.nextInt(60) + (rng.nextDouble() < 0.1 ? 60 : 0)];
      if (day == 3) scores[4] = 180;
      final total = scores.fold(0, (a, b) => a + b);
      out.add({
        'id': '${at.millisecondsSinceEpoch}',
        'at': at.toIso8601String(),
        'mode': 'Volées libres',
        'kind': 'training',
        'drill': 'volleys',
        'winner': null,
        'players': [
          {
            'id': 'owner',
            'name': 'Thibs',
            'won': false,
            'darts': 30,
            'score': total,
            'value': total / 10,
            'best': scores.reduce(math.max),
            'volleys': 10,
            'scores': scores,
          },
        ],
      });
    }
  }
  return out.reversed.toList();
}

/// Une manche de 501 simulée : tours au format de l'historique.
Map<String, Object?> _leg(math.Random rng, double skill) {
  var rem = 501, darts = 0, scored = 0, best = 0, tries = 0, hits = 0;
  final rows = <Map<String, Object?>>[];
  while (rem > 0 && rows.length < 30) {
    final start = rem;
    var sum = 0;
    var bust = false;
    final labels = <String>[];
    for (var i = 0; i < 3; i++) {
      DartThrow d;
      if (rem <= 40 && rem.isEven) {
        tries++;
        d = rng.nextDouble() < 0.35 ? DartThrow.double(rem ~/ 2) : DartThrow(rem ~/ 2);
      } else {
        final r = rng.nextDouble();
        d = r < skill * 0.6 ? const DartThrow.triple(20) : (r < 0.75 ? const DartThrow(20) : const DartThrow(5));
        if (rem - d.score < 2) d = DartThrow(rem.isOdd ? 1 : 2);
      }
      darts++;
      labels.add(d.label);
      rem -= d.score;
      if (rem < 0 || rem == 1) {
        bust = true;
        break;
      }
      sum += d.score;
      if (rem == 0) {
        hits++;
        break;
      }
    }
    if (bust) {
      rem = start;
    } else {
      scored += sum;
      best = math.max(best, sum);
    }
    rows.add({'leg': 1, 'darts': labels, 'total': bust ? 0 : sum, 'rest': rem, 'bust': bust});
  }
  return {
    'darts': darts,
    'scored': scored,
    'best': best,
    'tries': tries,
    'hits': hits,
    'value': scored / darts * 3,
    'turns': rows,
  };
}

Future<void> _font(String family, String path) async {
  final l = FontLoader(family)..addFont(rootBundle.load(path));
  await l.load();
}

void main() {
  test("stats calculées depuis l'historique", () {
    final s = OwnerStats(fakeHistory(), now: now);
    expect(s.isEmpty, isFalse);
    expect(s.averageNow, isNotNull);
    expect(s.checkoutPct, inInclusiveRange(1, 100));
    expect(s.weekly.length, 12);
    expect(s.records, isNotEmpty);
    expect(s.doubles, isNotEmpty);
    expect(s.rivals.map((r) => r.name), contains('Invités'));
    expect(s.nemesis?.name, 'Max');
    expect(s.aimReport('T20').side, -1);
    expect(s.monthReport(2026, 11).tiles.length, 6);
    expect(s.monthReport(2026, 11).levels.length, 30);
    expect(parseDart('T20'), const DartThrow.triple(20));
    expect(parseDart('BULL'), DartThrow.bull);
  });

  test('stats sans historique', () {
    final s = OwnerStats(const [], now: now);
    expect(s.records, isEmpty);
    expect(s.seriesCards.length, 6);
    expect(s.monthReport(2026, 11).tiles.length, 6);
    expect(s.aimReport('Doubles').isEmpty, isTrue);
  });

  testWidgets('écrans de stats sans débordement', (tester) async {
    await tester.runAsync(() async {
      await _font('Inter', 'assets/fonts/Inter.ttf');
      await _font('Nunito', 'assets/fonts/Nunito.ttf');
      await _font('packages/lucide_icons_flutter/Lucide', 'packages/lucide_icons_flutter/assets/lucide.ttf');
    });
    tester.view.physicalSize = const Size(1024, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final out = Platform.environment['SHOTS'];

    Future<void> shot(String name, Widget screen) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Inter', scaffoldBackgroundColor: Td.beton),
          home: RepaintBoundary(key: ValueKey(name), child: screen),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull, reason: name);
      if (out == null) return;
      final ro = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
      await tester.runAsync(() async {
        final img = await ro.toImage();
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    final h = fakeHistory();
    final s = OwnerStats(h, now: now);
    for (final tab in ['Résumé', 'X01', 'Entraînement', 'Potes', 'Cible']) {
      await shot('stats_$tab', StatsScreen(history: h, now: now, initialTab: tab));
      await shot('stats_vide_$tab', StatsScreen(history: const [], now: now, initialTab: tab));
    }
    await shot('stats_mois', MonthStatsScreen(stats: s, year: 2026, month: 11));
    await shot('stats_mois_octobre', MonthStatsScreen(stats: s, year: 2026, month: 10));
    await shot('stats_vide_mois', MonthStatsScreen(stats: OwnerStats(const [], now: now), year: 2026, month: 11));
  });
}
