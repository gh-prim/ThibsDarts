import 'package:darts_engine/darts_engine.dart';
import 'package:test/test.dart';

const t20 = DartThrow.triple(20);
const s20 = DartThrow.single(20);
const miss = DartThrow.miss();

void main() {
  test('série T20 : réussites, suite et fin', () {
    final g = TrainingGame('Thibs', target: const TrainingTarget(20, 3), darts: 6);
    for (final d in [t20, t20, s20]) {
      g.throwDart(d);
    }
    expect(g.awaitingNextPlayer, isTrue);
    expect(g.isFinished, isFalse);
    g.nextPlayer();
    for (final d in [t20, t20, t20]) {
      g.throwDart(d);
    }
    expect(g.isFinished, isTrue);
    expect(g.hits, 5);
    expect(g.bestStreak, 3);
    expect(g.rate, 83);
    expect(g.round, 2);
  });

  test('bull : 25 et 50 comptent', () {
    final g = TrainingGame('Thibs', target: TrainingTarget.bull, darts: 3);
    for (final d in [DartThrow.bull, DartThrow.outerBull, miss]) {
      g.throwDart(d);
    }
    expect(g.hits, 2);
    expect(g.isFinished, isTrue);
  });

  test('correction rejoue la série', () {
    final g = TrainingGame('Thibs', target: const TrainingTarget(16, 2), darts: 15);
    g.throwDart(miss);
    g.throwDart(const DartThrow.double(16));
    g.correctDart(0, const DartThrow.double(16));
    expect(g.hits, 2);
    expect(g.bestStreak, 2);
    expect(g.thrown, 2);
  });

  test('volées libres : moyenne, meilleure volée, fin', () {
    final g = VolleyGame('Thibs', volleys: 2);
    for (final d in [t20, t20, t20]) {
      g.throwDart(d);
    }
    expect(g.max180, 1);
    expect(g.isFinished, isFalse);
    g.nextPlayer();
    for (final d in [s20, miss, const DartThrow.triple(19)]) {
      g.throwDart(d);
    }
    expect(g.isFinished, isTrue);
    expect(g.scores, [180, 77]);
    expect(g.best, 180);
    expect(g.average, closeTo(128.5, 0.01));
  });

  test('volées libres sans fin, volée courte', () {
    final g = VolleyGame('Thibs', volleys: 0);
    g.throwDart(t20);
    g.nextPlayer();
    expect(g.done, 1);
    expect(g.scores, [60]);
    expect(g.isFinished, isFalse);
  });
}
