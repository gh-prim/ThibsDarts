import 'dart:math' as math;

import 'package:darts_engine/darts_engine.dart';
import 'package:test/test.dart';

/// Position du milieu d'une case double, décalée de [deg] degrés (sens horaire).
(double, double) mid(int sector, [double deg = 0]) {
  const order = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5];
  final a = (order.indexOf(sector) * 18 + deg) * math.pi / 180;
  return (166 * math.sin(a), -166 * math.cos(a));
}

void main() {
  test('escalier à 60 % : 3 réussites et 2 ratés reviennent au départ', () {
    var l = 1.0;
    for (final ok in [true, true, true, false, false]) {
      l = coachStep(l, ok);
    }
    expect(l, closeTo(1.0, 1e-9));
  });

  test('zone : 100 % au niveau 0, 25 % au niveau 3', () {
    expect(zoneFraction(0), 1);
    expect(zoneFraction(3), closeTo(0.25, 1e-9));
  });

  test('écart au milieu du double : tangentiel dans le sens horaire', () {
    final (x, y) = mid(16, 3);
    final e = aimError(const DartThrow.double(16), x, y);
    expect(e.radial, closeTo(0, 0.01));
    expect(e.tangential, closeTo(166 * 3 * math.pi / 180, 0.01));
  });

  test('dans la zone : la bonne case et assez près du milieu', () {
    const d16 = DartThrow.double(16);
    final (x, y) = mid(16, 6);
    expect(inZone(d16, d16, x, y, 1), isTrue);
    expect(inZone(d16, d16, x, y, 0.5), isFalse);
    final (x2, y2) = mid(16, 2);
    expect(inZone(d16, d16, x2, y2, 0.5), isTrue);
    expect(inZone(d16, const DartThrow.single(16), x2, y2, 1), isFalse);
  });

  test('profil : les doubles jamais tentés et fréquents passent en premier', () {
    final tries = [for (var i = 0; i < 20; i++) DoubleTry(const DartThrow.double(20), true)];
    final p = CoachProfile(tries: tries);
    expect(p.weakest.first.label, isNot('D20'));
    expect(p.skills['D20']!.pct, 100);
    expect(p.acquired.label, 'D20');
  });

  test('profil : biais moyen des fléchettes', () {
    final (x, y) = mid(16, -4);
    final p = CoachProfile(
      tries: [DoubleTry(const DartThrow.double(16), false, x: x, y: y)],
    );
    expect(p.skills['D16']!.tangential, lessThan(-10));
  });

  test('plan : 2 doubles faibles, sorties, pression', () {
    final plan = coachPlan(CoachProfile());
    expect(plan.map((s) => s.kind), [
      CoachStepKind.doubles,
      CoachStepKind.doubles,
      CoachStepKind.checkouts,
      CoachStepKind.pressure,
    ]);
  });

  CoachSession session() => CoachSession(
    'Thibs',
    plan: const [
      CoachStep(CoachStepKind.doubles, target: DartThrow.double(16), count: 2),
      CoachStep(CoachStepKind.checkouts, count: 2),
      CoachStep(CoachStepKind.pressure, target: DartThrow.double(20), count: 1),
    ],
    levels: CoachLevels(),
    seed: 7,
  );

  test('séance : la zone se resserre après des touches, figée pendant la volée', () {
    final g = session();
    final (x, y) = mid(16);
    for (var i = 0; i < 3; i++) {
      g.throwAt(const DartThrow.double(16), x, y);
      expect(g.zone, 1);
    }
    g.nextPlayer();
    expect(g.zone, lessThan(1));
    expect(g.levels.zone(const DartThrow.double(16)), closeTo(1.2, 1e-9));
  });

  test('séance : doubles puis sorties, check-out réussi', () {
    final g = session();
    final (x, y) = mid(16);
    for (var v = 0; v < 2; v++) {
      for (var i = 0; i < 3; i++) {
        g.throwAt(const DartThrow.double(16), x, y);
      }
      g.nextPlayer();
    }
    expect(g.step.kind, CoachStepKind.checkouts);
    final score = g.remaining;
    expect(score, inInclusiveRange(2, 40));
    final route = g.hint!;
    for (final d in route) {
      g.throwAt(d, null, null);
    }
    expect(g.checkouts.single.ok, isTrue);
    expect(g.levels.checkout, closeTo(0.4, 1e-9));
    g.nextPlayer();
    expect(g.current!.score, isNot(0));
  });

  test('pression : chrono fini, la volée compte comme ratée', () {
    final g = CoachSession(
      'Thibs',
      plan: const [CoachStep(CoachStepKind.pressure, target: DartThrow.double(20), count: 1)],
      levels: CoachLevels(pressure: 2),
    );
    expect(g.ghostVolleys, 1);
    expect(g.remaining, 40);
    g.timeUp();
    expect(g.isFinished, isTrue);
    expect(g.checkouts.single.ok, isFalse);
    expect(g.ghostRest, 0);
  });

  test('correction : rejoue avec les positions', () {
    final g = session();
    final (x, y) = mid(16);
    g.throwAt(const DartThrow.single(16), x, y - 30);
    g.correctAt(0, const DartThrow.double(16), x: x, y: y);
    expect(g.shots.single.ok, isTrue);
    expect(g.shots.single.x, closeTo(x, 1e-9));
  });

  test('niveaux : aller-retour JSON', () {
    final l = CoachLevels(zones: {'D16': 1.234}, checkout: 2.5, pressure: 1);
    final b = CoachLevels.fromJson(l.toJson());
    expect(b.zones['D16'], 1.23);
    expect(b.checkout, 2.5);
  });
}
