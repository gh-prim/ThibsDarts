import 'dart:math' as math;

import 'package:darts_engine/darts_engine.dart';
import 'package:test/test.dart';

/// Position (mm) au milieu d'une case, décalée de [dr] vers l'extérieur.
(double, double) at(DartThrow d, {double dr = 0}) {
  const order = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5];
  if (d.sector == 25 || d.isMiss) return (0, 0);
  final r = (d.multiplier == 2 ? 166.0 : (d.multiplier == 3 ? 103.0 : 135.0)) + dr;
  final a = order.indexOf(d.sector) * 18 * math.pi / 180;
  return (r * math.sin(a), -r * math.cos(a));
}

void volley(DoublesProSession g, List<DartThrow> darts) {
  for (final d in darts) {
    if (g.awaitingNextPlayer || g.isFinished) break;
    final (x, y) = at(d);
    g.throwAt(d, x, y);
  }
  g.nextPlayer();
}

void main() {
  test('diagnostic : 15 sur D16 puis 15 sur D20, écart mesuré', () {
    final g = DoublesProSession('Thibs', blocks: const [DpBlock.diagnostic]);
    expect(g.aim, const DartThrow.double(16));
    for (var v = 0; v < 5; v++) {
      for (var i = 0; i < 3; i++) {
        final (x, y) = at(const DartThrow.double(16), dr: 2);
        g.throwAt(const DartThrow.double(16), x, y);
      }
      g.nextPlayer();
    }
    expect(g.aim, const DartThrow.double(20));
    final d = g.diagnosticOf(const DartThrow.double(16));
    expect(d.hit, 15);
    expect(d.bias.radial, closeTo(2, 0.01));
    for (var v = 0; v < 5; v++) {
      volley(g, const [DartThrow.miss(), DartThrow.single(20), DartThrow.double(20)]);
    }
    expect(g.isFinished, isTrue);
    expect(g.hitsOf(DpBlock.diagnostic), (ok: 20, total: 30));
  });

  test('chaînes : le simple fait descendre, D1 raté finit la chaîne', () {
    final g = DoublesProSession('Thibs', blocks: const [DpBlock.chains]);
    expect(g.remaining, 32);
    expect(g.aim, const DartThrow.double(16));
    g.throwAt(const DartThrow.single(16), null, null);
    expect(g.remaining, 16);
    expect(g.aim, const DartThrow.double(8));
    g.throwAt(const DartThrow.double(8), null, null);
    expect(g.awaitingNextPlayer, isTrue);
    expect(g.runsOf(DpBlock.chains), (ok: 1, total: 1));
    g.nextPlayer();
    // Chaîne du 20 : S20, S10, S5 laisse 5, impair : ratée.
    expect(g.remaining, 40);
    volley(g, const [DartThrow.single(20), DartThrow.single(10), DartThrow.single(5)]);
    expect(g.runs.last.ok, isFalse);
    expect(g.chainAverage, 2);
  });

  test('aléatoire : 30 doubles, jamais deux fois le même à la suite', () {
    final g = DoublesProSession('Thibs', blocks: const [DpBlock.random], seed: 7);
    expect(g.randomTargets.length, dpRandomDarts);
    for (var i = 1; i < g.randomTargets.length; i++) {
      expect(g.randomTargets[i], isNot(g.randomTargets[i - 1]));
    }
    while (!g.isFinished) {
      volley(g, [g.aim!, const DartThrow.miss(), const DartThrow.miss()]);
    }
    expect(g.hitsOf(DpBlock.random).total, 30);
    expect(g.scoreOf(0), 33);
  });

  test('échelle : réussi on monte, raté retour à 32', () {
    final g = DoublesProSession('Thibs', blocks: const [DpBlock.ladder]);
    expect(g.remaining, 32);
    volley(g, const [DartThrow.double(16)]);
    expect(g.rung, 1);
    expect(g.remaining, 40);
    for (var i = 0; i < 3; i++) {
      volley(g, const [DartThrow.miss(), DartThrow.miss(), DartThrow.miss()]);
    }
    expect(g.rung, 0);
    expect(g.remaining, 32);
    expect(g.bestLadder, 32);
    // Bust : retour au début de la volée.
    volley(g, const [DartThrow.single(20), DartThrow.single(16)]);
    expect(g.remaining, 32);
  });

  test('séance complète et correction rejouée', () {
    final g = DoublesProSession('Thibs', seed: 3);
    var guard = 0;
    while (!g.isFinished && guard++ < 300) {
      while (!g.awaitingNextPlayer && !g.isFinished) {
        final a = g.aim ?? suggestCheckout(g.remaining, dartsLeft: 3 - g.currentTurn.length)!.first;
        g.throwAt(a, null, null);
      }
      g.nextPlayer();
    }
    expect(g.isFinished, isTrue);
    expect(g.blockIndex, DpBlock.values.length - 1);
    expect(g.bestLadder, 121);

    final h = DoublesProSession('Thibs', blocks: const [DpBlock.diagnostic]);
    h.throwAt(const DartThrow.single(16), 0, 0);
    h.correctAt(0, const DartThrow.double(16));
    expect(h.hitsOf(DpBlock.diagnostic), (ok: 1, total: 1));
  });

  test('dehors, dedans, à côté', () {
    const t = DartThrow.double(20);
    expect(dpMissOf(t, const DartThrow.miss(), 0, -175), DpMiss.outside);
    expect(dpMissOf(t, const DartThrow.single(20), 0, -158), DpMiss.inside);
    expect(dpMissOf(t, const DartThrow.double(1), 40, -160), DpMiss.side);
    expect(dpMissOf(t, const DartThrow.single(20), null, null), DpMiss.inside);
  });
}
