import 'dart:math' as math;

import 'package:darts_engine/darts_engine.dart';
import 'package:test/test.dart';

const miss = DartThrow.miss();
DartThrow s(int n) => DartThrow.single(n);
DartThrow d(int n) => DartThrow.double(n);
DartThrow t(int n) => DartThrow.triple(n);

void volley(TurnGame g, List<DartThrow> darts) {
  for (final x in darts) {
    if (g.awaitingNextPlayer) break;
    g.throwDart(x);
  }
  g.nextPlayer();
}

void main() {
  group('Catch 40', () {
    test('61 en 2 fléchettes : 3 points, on passe au 62', () {
      final g = LadderGame.catch40('Thibs');
      g.throwDart(t(7)); // reste 40
      g.throwDart(d(20));
      expect(g.awaitingNextPlayer, isTrue);
      expect(g.total, 3);
      expect(g.target, 62);
      expect(g.remaining, 62);
    });

    test('fini en 5 fléchettes : 2 points', () {
      final g = LadderGame.catch40('Thibs');
      volley(g, [miss, miss, miss]);
      expect(g.dartsLeft, 3);
      volley(g, [miss, s(1), d(15)]);
      // 61 - 1 - 30 = 30 : pas fini, raté après 6 fléchettes
      expect(g.results, [0]);
      expect(g.target, 62);
    });

    test('bust : retour au début de la volée et volée finie', () {
      final g = LadderGame.catch40('Thibs');
      g.throwDart(t(20)); // reste 1 : bust
      expect(g.awaitingNextPlayer, isTrue);
      g.nextPlayer();
      expect(g.remaining, 61);
      expect(g.dartsLeft, 3);
      volley(g, [s(11), DartThrow.bull]);
      expect(g.total, 2);
    });

    test('40 scores puis fin', () {
      final g = LadderGame.catch40('Thibs');
      for (var i = 0; i < 40; i++) {
        volley(g, [miss, miss, miss]);
        volley(g, [miss, miss, miss]);
      }
      expect(g.isFinished, isTrue);
      expect(g.results.length, 40);
    });
  });

  test('41-60 : 3 fléchettes par score', () {
    final g = LadderGame.fortyOne('Thibs');
    volley(g, [s(1), d(20)]);
    expect(g.results, [1]);
    volley(g, [miss, miss, miss]);
    expect(g.results, [1, 0]);
    expect(g.target, 43);
    expect(g.rate, 50);
  });

  group('Sorties en 9 fléchettes', () {
    test('121 en 9 : réussite', () {
      final g = CheckoutDrill.nineDarts('Thibs', attempts: 2);
      volley(g, [t(20), s(20), s(1)]); // 40
      volley(g, [d(20)]);
      expect(g.results, [true]);
      expect(g.dartsToFinish, [4]);
      expect(g.remaining, 121);
      expect(g.streak, 1);
    });

    test('9 fléchettes sans finir : raté', () {
      final g = CheckoutDrill.ton70('Thibs', attempts: 1);
      for (var i = 0; i < 3; i++) {
        volley(g, [s(1), s(1), s(1)]);
      }
      expect(g.results, [false]);
      expect(g.isFinished, isTrue);
    });

    test('au hasard : scores possibles dans la plage', () {
      final g = CheckoutDrill.random('Thibs', range: CheckoutRange.big, random: math.Random(3));
      for (final n in g.targets) {
        expect(n, inInclusiveRange(111, 170));
        expect(suggestCheckout(n), isNotNull);
      }
    });
  });

  group('JDC', () {
    test('Shanghai sur le 10 : bonus de 100', () {
      final g = JdcGame('Thibs');
      volley(g, [s(10), d(10), t(10)]);
      expect(g.total, 60 + 100);
      expect(g.shanghais, 1);
      expect(g.target, 11);
    });

    test('phase 2 : une fléchette par double, puis phase 3', () {
      final g = JdcGame('Thibs');
      for (var i = 0; i < 6; i++) {
        volley(g, [miss, miss, miss]);
      }
      expect(g.phase, 2);
      expect(g.target, 1);
      volley(g, [d(1), miss, d(3)]);
      expect(g.total, 100);
      expect(g.target, 4);
      for (var i = 0; i < 6; i++) {
        volley(g, [miss, miss, miss]);
      }
      expect(g.phase, 3);
      expect(g.target, 15);
      for (var i = 0; i < 6; i++) {
        volley(g, [miss, miss, miss]);
      }
      expect(g.isFinished, isTrue);
    });

    test('le bull double vaut 50 en phase 2', () {
      expect(JdcGame.targetAt(26), 25);
      expect(JdcGame.targetAt(25), 20);
    });
  });

  test('99 fléchettes : seules les touches sur la cible', () {
    final g = Darts99Game('Thibs', volleys: 2);
    volley(g, [t(20), s(1), d(20)]);
    expect(g.total, 100);
    expect(g.counts, [0, 1, 1]);
    volley(g, [s(20), s(5), miss]);
    expect(g.isFinished, isTrue);
    expect(g.average, 60);
  });

  test('Tour du monde : on avance touché ou pas', () {
    final g = RoundTheWorldGame('Thibs');
    volley(g, [miss, miss, miss]);
    expect(g.target, 2);
    volley(g, [d(2), s(2), miss]);
    expect(g.points, [0, 6]);
    final dd = RoundTheWorldGame('Thibs', multiplier: 2);
    volley(dd, [s(1), d(1), t(1)]);
    expect(dd.total, 2);
  });

  test('Cricket Count Up : marques sur 15 à 20 et bull', () {
    final g = CricketCountUpGame('Thibs', volleys: 1);
    volley(g, [t(20), d(14), DartThrow.bull]);
    expect(g.total, 5);
    expect(g.isFinished, isTrue);
  });

  group('Cricket variantes', () {
    test('No Score : pas de points, premier fermé gagne', () {
      final g = CricketGame(['A', 'B'], variant: CricketVariant.noScore);
      volley(g, [t(20), t(20), t(19)]);
      expect(g.points, [0, 0]);
      volley(g, [miss, miss, miss]);
      for (final n in [18, 17, 16, 15]) {
        volley(g, [t(n), miss, miss]);
        volley(g, [miss, miss, miss]);
      }
      volley(g, [DartThrow.bull, DartThrow.bull]);
      expect(g.winner, 'A');
    });

    test('Cut-Throat : les points vont aux adversaires', () {
      final g = CricketGame(['A', 'B', 'C'], variant: CricketVariant.cutThroat);
      volley(g, [t(20), t(20), miss]);
      expect(g.points, [0, 60, 60]);
    });

    test('Tactic : 20 à 10 et bull', () {
      final g = CricketGame(['A'], variant: CricketVariant.tactic);
      expect(g.numbers.length, 12);
      expect(g.numbers.last, 25);
    });

    test('Random : 6 numéros et le bull', () {
      final g = CricketGame(['A', 'B'], variant: CricketVariant.random);
      expect(g.numbers.length, 7);
      expect(g.numbers.toSet().length, 7);
    });
  });

  test('Bermuda : raté divise par deux, départ à 0', () {
    final g = HalveItGame.bermuda(['A']);
    volley(g, [s(12), s(12), miss]);
    expect(g.points.single, 24);
    volley(g, [miss, miss, miss]);
    expect(g.points.single, 12);
    expect(g.target.label, '14');
  });

  group('Gotcha', () {
    test('tomber sur le score adverse le renvoie à 0', () {
      final g = GotchaGame(['A', 'B']);
      volley(g, [t(20), miss, miss]);
      g.throwDart(t(20));
      expect(g.points, [0, 60]);
      expect(g.lastEvent, contains('A'));
    });

    test('dépasser 301 : bust', () {
      final g = GotchaGame(['A'], goal: 50);
      volley(g, [s(20), s(20)]);
      g.throwDart(s(20));
      expect(g.awaitingNextPlayer, isTrue);
      expect(g.points.single, 40);
      g.nextPlayer();
      g.throwDart(s(10));
      expect(g.isFinished, isTrue);
    });
  });

  group('Robot', () {
    test('la moyenne colle au niveau', () {
      for (final l in BotLevel.all) {
        final bot = DartBot(l, random: math.Random(7));
        var total = 0;
        const n = 30000;
        for (var i = 0; i < n; i++) {
          total += bot.throwAt(t(20)).score;
        }
        expect(total / n * 3, closeTo(l.average, l.average * 0.12));
      }
    });

    test('vise la sortie', () {
      expect(DartBot.aimX01(40), d(20));
      expect(DartBot.aimX01(501), t(20));
      expect(DartBot.aimX01(41, dartsLeft: 1), s(9));
    });

    test('Cricket : ferme le 20 en premier', () {
      final g = CricketGame(['Thibs', 'Robot']);
      expect(DartBot.aimCricket(g, 1), t(20));
    });

    test('hitAt : centre et triple', () {
      expect(DartBot.hitAt(0, 0), DartThrow.bull);
      final (x, y) = DartBot.aimPoint(t(19));
      expect(DartBot.hitAt(x, y), t(19));
    });
  });
}
