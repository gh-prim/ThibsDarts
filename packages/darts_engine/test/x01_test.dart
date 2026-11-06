import 'package:darts_engine/darts_engine.dart';
import 'package:test/test.dart';

void main() {
  group('DartThrow', () {
    test('scores et libellés', () {
      expect(const DartThrow.triple(20).score, 60);
      expect(const DartThrow.triple(20).callout, 'TRIPLE 20');
      expect(DartThrow.bull.score, 50);
      expect(DartThrow.bull.label, 'BULL');
      expect(const DartThrow.miss().score, 0);
    });
  });

  group('X01', () {
    test('un tour normal enlève les points', () {
      final g = X01Game(playerNames: ['Thibs', 'Max']);
      expect(g.throwDart(const DartThrow.triple(20)), ThrowOutcome.scored);
      g.throwDart(const DartThrow.triple(20));
      expect(g.throwDart(const DartThrow.triple(20)), ThrowOutcome.turnOver);
      expect(g.currentPlayer.remaining, 321);
      g.nextPlayer();
      expect(g.currentPlayer.name, 'Max');
    });

    test('bust : retour au score du début de tour', () {
      final g = X01Game(playerNames: ['Thibs'], startScore: 32);
      g.throwDart(const DartThrow.single(20));
      expect(g.throwDart(const DartThrow.triple(10)), ThrowOutcome.bust);
      expect(g.currentPlayer.remaining, 32);
      expect(g.awaitingNextPlayer, isTrue);
    });

    test('double out obligatoire', () {
      final g = X01Game(playerNames: ['Thibs'], startScore: 40);
      expect(g.throwDart(const DartThrow.triple(10).copyWithSector(20, 2)), ThrowOutcome.checkout);
      expect(g.winner?.name, 'Thibs');

      final g2 = X01Game(playerNames: ['Thibs'], startScore: 40);
      g2.throwDart(const DartThrow.single(20));
      expect(g2.throwDart(const DartThrow.single(20)), ThrowOutcome.bust);
    });

    test('rester à 1 en double out = bust', () {
      final g = X01Game(playerNames: ['Thibs'], startScore: 21);
      expect(g.throwDart(const DartThrow.single(20)), ThrowOutcome.bust);
    });

    test('single out accepte une fin en simple', () {
      final g = X01Game(playerNames: ['Thibs'], startScore: 20, doubleOut: false);
      expect(g.throwDart(const DartThrow.single(20)), ThrowOutcome.checkout);
    });

    test('annuler la dernière fléchette', () {
      final g = X01Game(playerNames: ['Thibs'], startScore: 32);
      g.throwDart(const DartThrow.single(20));
      g.throwDart(const DartThrow.triple(10)); // bust
      g.undoLastDart();
      expect(g.currentPlayer.remaining, 12);
      expect(g.awaitingNextPlayer, isFalse);
      expect(g.throwDart(const DartThrow.double(6)), ThrowOutcome.checkout);
    });

    test('moyenne 3 fléchettes', () {
      final g = X01Game(playerNames: ['Thibs']);
      for (var i = 0; i < 3; i++) {
        g.throwDart(const DartThrow.single(20));
      }
      expect(g.currentPlayer.average, 60);
    });
  });

  group('checkout', () {
    test('sorties classiques', () {
      expect(suggestCheckout(170), [const DartThrow.triple(20), const DartThrow.triple(20), DartThrow.bull]);
      expect(suggestCheckout(40), [const DartThrow.double(20)]);
      expect(suggestCheckout(32), [const DartThrow.double(16)]);
      expect(suggestCheckout(100)!.length, 2);
    });

    test('impossible', () {
      expect(suggestCheckout(169), isNull);
      expect(suggestCheckout(1), isNull);
      expect(suggestCheckout(100, dartsLeft: 1), isNull);
    });
  });
}

extension on DartThrow {
  DartThrow copyWithSector(int s, int m) => DartThrow(s, m);
}
