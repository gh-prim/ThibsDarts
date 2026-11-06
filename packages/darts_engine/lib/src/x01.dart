import 'checkout.dart';
import 'dart_throw.dart';

/// Résultat d'une fléchette dans une partie X01.
enum ThrowOutcome {
  /// Fléchette comptée, le tour continue.
  scored,

  /// Troisième fléchette : le tour est fini, on attend le retrait des fléchettes.
  turnOver,

  /// Score dépassé ou fini sans double : le score revient au début du tour.
  bust,

  /// Le joueur finit la manche.
  checkout,
}

class X01Player {
  final String name;
  int remaining;
  final List<List<DartThrow>> turns = [];

  X01Player(this.name, this.remaining);

  /// Moyenne sur 3 fléchettes.
  double get average {
    final darts = turns.fold<int>(0, (n, t) => n + t.length);
    if (darts == 0) return 0;
    final scored = turns.fold<int>(0, (n, t) => n + t.fold<int>(0, (m, d) => m + d.score));
    return scored / darts * 3;
  }
}

/// Partie 301 / 501 (une manche), double out en option.
class X01Game {
  final int startScore;
  final bool doubleOut;
  final List<X01Player> players;

  int _current = 0;
  final List<DartThrow> _turn = [];
  int _turnStart;
  bool _turnClosed = false;
  X01Player? winner;

  X01Game({required List<String> playerNames, this.startScore = 501, this.doubleOut = true})
    : assert(playerNames.isNotEmpty),
      players = [for (final n in playerNames) X01Player(n, startScore)],
      _turnStart = startScore;

  X01Player get currentPlayer => players[_current];
  List<DartThrow> get currentTurn => List.unmodifiable(_turn);
  int get dartsLeft => 3 - _turn.length;

  /// Score du joueur actif au début du tour (pour le bust).
  int get turnStartScore => _turnStart;

  /// Index du joueur actif.
  int get currentIndex => _current;

  /// Joueur qui tirera après le joueur actif.
  X01Player get nextPlayerInLine => players[(_current + 1) % players.length];
  bool get isFinished => winner != null;

  /// Le tour est fini (3 fléchettes, bust ou checkout) : il faut appeler [nextPlayer].
  bool get awaitingNextPlayer => _turnClosed;

  /// Suggestion de sortie pour le joueur actif, ou null.
  List<DartThrow>? get checkoutHint =>
      doubleOut && !_turnClosed ? suggestCheckout(currentPlayer.remaining, dartsLeft: dartsLeft) : null;

  ThrowOutcome throwDart(DartThrow dart) {
    if (isFinished) throw StateError('Partie terminée');
    if (_turnClosed) throw StateError('Tour fini, appelle nextPlayer()');

    _turn.add(dart);
    final p = currentPlayer;
    final left = p.remaining - dart.score;

    final bust = left < 0 || (doubleOut && left == 1) || (doubleOut && left == 0 && !dart.isDouble);
    if (bust) {
      p.remaining = _turnStart;
      _closeTurn();
      return ThrowOutcome.bust;
    }

    p.remaining = left;
    if (left == 0) {
      winner = p;
      _closeTurn();
      return ThrowOutcome.checkout;
    }
    if (_turn.length == 3) {
      _closeTurn();
      return ThrowOutcome.turnOver;
    }
    return ThrowOutcome.scored;
  }

  /// Fléchettes retirées : on passe au joueur suivant.
  void nextPlayer() {
    if (isFinished) return;
    if (!_turnClosed) _closeTurn();
    _turn.clear();
    _turnClosed = false;
    _current = (_current + 1) % players.length;
    _turnStart = currentPlayer.remaining;
  }

  /// Annule la dernière fléchette du tour en cours.
  void undoLastDart() {
    if (_turn.isEmpty) return;
    _replay(List.of(_turn)..removeLast());
  }

  /// Corrige la fléchette [index] (0 à 2) du tour en cours et recalcule le tour.
  /// Si la correction fait finir ou buster plus tôt, les fléchettes suivantes sont ignorées.
  ThrowOutcome? correctDart(int index, DartThrow dart) {
    if (index < 0 || index > _turn.length || index > 2) throw RangeError.index(index, _turn);
    final darts = List.of(_turn);
    if (index == darts.length) {
      darts.add(dart);
    } else {
      darts[index] = dart;
    }
    return _replay(darts);
  }

  ThrowOutcome? _replay(List<DartThrow> darts) {
    if (_turnClosed) {
      currentPlayer.turns.removeLast();
      _turnClosed = false;
      winner = null;
    }
    _turn.clear();
    currentPlayer.remaining = _turnStart;
    ThrowOutcome? last;
    for (final d in darts) {
      last = throwDart(d);
      if (_turnClosed) break;
    }
    return last;
  }

  void _closeTurn() {
    _turnClosed = true;
    currentPlayer.turns.add(List.of(_turn));
  }
}
