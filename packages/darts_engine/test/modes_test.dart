import 'package:darts_engine/darts_engine.dart';
import 'package:test/test.dart';

void turn(TurnGame g, List<DartThrow> darts) {
  for (final d in darts) {
    g.throwDart(d);
  }
  g.nextPlayer();
}

const t20 = DartThrow.triple(20);
const miss = DartThrow.miss();

void main() {
  test('cricket : fermer puis marquer', () {
    final g = CricketGame(['A', 'B']);
    turn(g, [t20, t20, miss]);
    expect(g.marks[0][0], 6);
    expect(g.points[0], 60);
    turn(g, [t20, miss, miss]);
    expect(g.points[1], 0);
    expect(g.isOpen(20), isFalse);
  });

  test('cricket : tout fermé et devant, gagné', () {
    final g = CricketGame(['A']);
    for (final n in [20, 19, 18, 17, 16, 15]) {
      turn(g, [DartThrow.triple(n), miss, miss]);
    }
    expect(g.isFinished, isFalse);
    g.throwDart(DartThrow.bull);
    g.throwDart(DartThrow.outerBull);
    expect(g.winner, 'A');
  });

  test('horloge : dans l\'ordre, de 1 à 20', () {
    final g = ClockGame(['A', 'B']);
    turn(g, [const DartThrow(1), const DartThrow(3), const DartThrow.double(2)]);
    expect(g.target[0], 3);
    expect(g.currentName, 'B');
  });

  test('shanghai : S, D, T au même tour', () {
    final g = ShanghaiGame(['A', 'B']);
    g.throwDart(const DartThrow(1));
    g.throwDart(const DartThrow.double(1));
    g.throwDart(const DartThrow.triple(1));
    expect(g.winner, 'A');
  });

  test('shanghai : au bout des manches, le meilleur gagne', () {
    final g = ShanghaiGame(['A', 'B'], rounds: 2);
    turn(g, [const DartThrow(1), miss, miss]);
    turn(g, [miss, miss, miss]);
    expect(g.target, 2);
    turn(g, [miss, miss, miss]);
    turn(g, [const DartThrow.double(2), miss, miss]);
    expect(g.winner, 'B');
  });

  test('killer : devenir killer puis éliminer', () {
    final g = KillerGame(['A', 'B'], numbers: [20, 6], lives: 1);
    g.throwDart(const DartThrow.double(20));
    expect(g.killer[0], isTrue);
    g.throwDart(const DartThrow.double(6));
    expect(g.winner, 'A');
  });

  test('halve-it : rien touché, score divisé', () {
    final g = HalveItGame(['A', 'B']);
    turn(g, [miss, miss, miss]);
    expect(g.points[0], 20);
    turn(g, [const DartThrow.triple(19), miss, miss]);
    expect(g.points[1], 97);
  });

  test('bob\'s 27 : double touché ou perdu', () {
    final g = Bobs27Game(['A']);
    turn(g, [const DartThrow.double(1), miss, miss]);
    expect(g.points[0], 29);
    expect(g.target, 2);
    turn(g, [miss, miss, miss]);
    expect(g.points[0], 25);
  });

  test('correction : rejoue le tour', () {
    final g = ClockGame(['A']);
    g.throwDart(miss);
    g.correctDart(0, const DartThrow(1));
    expect(g.target[0], 2);
    expect(g.currentTurn.length, 1);
  });

  test('killer : se tuer finit le tour', () {
    final g = KillerGame(['A', 'B', 'C'], numbers: [20, 6, 3], lives: 1);
    g.throwDart(const DartThrow.double(20));
    g.throwDart(const DartThrow.double(20));
    expect(g.isOut(0), isTrue);
    expect(g.awaitingNextPlayer, isTrue);
    g.nextPlayer();
    expect(g.currentName, 'B');
  });

  test('killer : un éliminé ne joue plus', () {
    final g = KillerGame(['A', 'B', 'C'], numbers: [20, 6, 3], lives: 1);
    turn(g, [const DartThrow.double(20), const DartThrow.double(6), miss]);
    expect(g.isOut(1), isTrue);
    expect(g.currentName, 'C');
    turn(g, [miss, miss, miss]);
    expect(g.currentName, 'A');
  });

  test('halve-it : fin après 9 manches', () {
    final g = HalveItGame(['A']);
    for (var i = 0; i < 9; i++) {
      expect(g.isFinished, isFalse);
      turn(g, [miss, miss, miss]);
    }
    expect(g.isFinished, isTrue);
    expect(g.points[0], 0);
  });

  test('bob\'s 27 : D20 puis bull, 21 manches', () {
    final g = Bobs27Game(['A']);
    for (var r = 1; r <= 20; r++) {
      expect(g.target, r);
      turn(g, [DartThrow.double(r), miss, miss]);
    }
    expect(g.target, 25);
    g.throwDart(DartThrow.bull);
    g.throwDart(miss);
    g.throwDart(miss);
    g.nextPlayer();
    expect(g.isFinished, isTrue);
    expect(g.points[0], 27 + 420 + 50);
  });

  test('correction : annule une victoire', () {
    final g = ShanghaiGame(['A', 'B']);
    g.throwDart(const DartThrow(1));
    g.throwDart(const DartThrow.double(1));
    g.throwDart(const DartThrow.triple(1));
    expect(g.isFinished, isTrue);
    g.correctDart(2, miss);
    expect(g.isFinished, isFalse);
    expect(g.points[0], 3);
  });

  test('égalité aux points', () {
    final g = HalveItGame(['A', 'B']);
    for (var i = 0; i < 9; i++) {
      turn(g, [miss, miss, miss]);
      turn(g, [miss, miss, miss]);
    }
    expect(g.isDraw, isTrue);
    expect(g.winners, [0, 1]);
  });
}
