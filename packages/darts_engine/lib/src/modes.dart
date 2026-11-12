import 'dart:math' as math;

import 'dart_throw.dart';

/// Modes de jeu autres que le X01.
enum GameMode {
  cricket,
  clock,
  shanghai,
  killer,
  halveIt,
  bobs27,
  bermuda,
  gotcha,
  catch40,
  nineDarts,
  randomCheckout,
  ton70,
  fortyOne,
  jdc,
  darts99,
  roundTheWorld,
  countUp,
  cricketCountUp;

  /// Entraînement solo (un seul joueur, écran d'entraînement).
  bool get solo => index >= GameMode.catch40.index;
}

/// Base commune : tours de 3 fléchettes, joueur suivant, correction par rejeu.
///
/// Chaque mode décrit seulement ce qu'une fléchette et une fin de tour changent.
/// Corriger une fléchette rejoue toute la partie depuis le début : l'état reste juste.
abstract class TurnGame {
  TurnGame(this.names) : assert(names.isNotEmpty);

  final List<String> names;

  final List<(int, List<DartThrow>)> _history = [];
  final List<DartThrow> _turn = [];
  int _current = 0;
  bool _closed = false;
  bool _endEarly = false;

  /// Nombre de tours joués par le joueur actif avant celui-ci (0 au premier tour).
  int _round = 0;

  /// Index du gagnant, ou null.
  int? winnerIndex;

  /// Tous les gagnants : plusieurs en cas d'égalité aux points.
  List<int> winners = const [];

  bool get isDraw => winners.length > 1;

  int get currentIndex => _current;
  String get currentName => names[_current];
  List<DartThrow> get currentTurn => List.unmodifiable(_turn);
  bool get awaitingNextPlayer => _closed;
  bool get isFinished => winnerIndex != null;
  String? get winner => winnerIndex == null ? null : names[winnerIndex!];

  /// Manche en cours, à partir de 1 (un tour par joueur et par manche).
  int get round => _round + 1;

  /// Joueur éliminé (Killer, Bob's 27) : il ne joue plus.
  bool isOut(int player) => false;

  /// Tours joués par un joueur, tour en cours compris (stats, historique).
  List<List<DartThrow>> turnsOf(int player) => [
    for (final (p, t) in _history)
      if (p == player) List.unmodifiable(t),
    if (!_closed && _current == player && _turn.isNotEmpty) List.unmodifiable(_turn),
  ];

  /// Prochain joueur encore en jeu.
  int get nextIndex {
    for (var i = 1; i <= names.length; i++) {
      final p = (_current + i) % names.length;
      if (!isOut(p)) return p;
    }
    return _current;
  }

  String get nextName => names[nextIndex];

  /// Score affiché pour un joueur (points, vies, cible...).
  int scoreOf(int player);

  // À écrire par chaque mode.
  void resetState();
  void onDart(int player, DartThrow d);
  void onTurnEnd(int player, List<DartThrow> turn) {}

  /// Appelé quand tout le monde a joué la manche.
  void onRoundEnd() {}

  /// Le mode ferme le tour avant 3 fléchettes (sortie, bust) : les suivantes sont ignorées.
  void endTurn() => _endEarly = true;

  /// Le mode peut fermer le tour avant 3 fléchettes (victoire).
  void finish(int player) {
    winnerIndex = player;
    winners = [player];
  }

  void throwDart(DartThrow d) {
    if (isFinished) throw StateError('Partie terminée');
    if (_closed) throw StateError('Tour fini, appelle nextPlayer()');
    _turn.add(d);
    onDart(_current, d);
    if (isFinished || _turn.length == 3 || isOut(_current) || _endEarly) _closeTurn();
  }

  void _closeTurn() {
    if (_closed) return;
    _closed = true;
    _endEarly = false;
    _history.add((_current, List.of(_turn)));
    if (!isFinished) onTurnEnd(_current, List.of(_turn));
  }

  void nextPlayer() {
    if (isFinished) return;
    if (!_closed) _closeTurn();
    if (isFinished) return;
    _turn.clear();
    _closed = false;
    final next = nextIndex;
    if (next <= _current || names.length == 1) {
      _round++;
      onRoundEnd();
    }
    _current = next;
  }

  /// Corrige la fléchette [index] (0 à 2) du tour en cours, ou en ajoute une.
  void correctDart(int index, DartThrow d) {
    final darts = List.of(_turn);
    if (index == darts.length) {
      darts.add(d);
    } else {
      darts[index] = d;
    }
    final turns = [for (final (p, t) in _history) (p, t)];
    if (_closed) turns.removeLast();
    _replay(turns, darts);
  }

  void _replay(List<(int, List<DartThrow>)> turns, List<DartThrow> current) {
    _history.clear();
    _turn.clear();
    _current = 0;
    _closed = false;
    _endEarly = false;
    _round = 0;
    winnerIndex = null;
    winners = const [];
    resetState();
    for (final (_, t) in turns) {
      for (final d in t) {
        if (_closed) break;
        throwDart(d);
      }
      if (!_closed) _closeTurn();
      if (isFinished) return;
      nextPlayer();
    }
    for (final d in current) {
      if (_closed) break;
      throwDart(d);
    }
  }

  /// Le joueur au meilleur score gagne (fin de partie aux points).
  void finishOnBestScore() {
    var best = -1 << 30;
    for (var i = 0; i < names.length; i++) {
      if (scoreOf(i) > best) best = scoreOf(i);
    }
    winners = [
      for (var i = 0; i < names.length; i++)
        if (scoreOf(i) == best) i,
    ];
    winnerIndex = winners.first;
  }
}

// MARK: Cricket

/// Variantes du Cricket.
enum CricketVariant {
  /// 20 à 15 et bull, on marque sur ce qui reste ouvert chez les autres.
  classic,

  /// Fermer seulement : pas de points, le premier qui ferme tout gagne.
  noScore,

  /// Les points vont aux adversaires qui n'ont pas fermé. Le moins de points gagne.
  cutThroat,

  /// 6 numéros tirés au hasard et le bull.
  random,

  /// 20 à 10 et le bull.
  tactic,
}

/// Cricket : fermer 20 à 15 et le bull (3 marques), marquer sur ce qui reste ouvert chez les autres.
class CricketGame extends TurnGame {
  CricketGame(super.names, {this.variant = CricketVariant.classic, List<int>? numbers})
    : numbers = numbers ?? numbersFor(variant) {
    resetState();
  }

  /// Ordre d'affichage du Cricket classique : 20, 19, 18, 17, 16, 15, bull.
  static const standard = [20, 19, 18, 17, 16, 15, 25];

  /// Numéros de la variante (tirés au hasard pour Random).
  static List<int> numbersFor(CricketVariant v, [math.Random? random]) => switch (v) {
    CricketVariant.tactic => const [20, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10, 25],
    CricketVariant.random => [
      ...((List.generate(20, (i) => i + 1)..shuffle(random)).take(6).toList()..sort((a, b) => b - a)),
      25,
    ],
    _ => standard,
  };

  final CricketVariant variant;

  /// Numéros en jeu, du plus grand au plus petit, bull à la fin.
  final List<int> numbers;

  late List<List<int>> marks;
  late List<int> points;

  /// Le moins de points gagne (Cut-Throat).
  bool get lowWins => variant == CricketVariant.cutThroat;

  @override
  void resetState() {
    marks = [for (final _ in names) List.filled(numbers.length, 0)];
    points = List.filled(names.length, 0);
  }

  @override
  int scoreOf(int player) => points[player];

  bool closedByAll(int i) => marks.every((m) => m[i] >= 3);

  /// Numéro encore ouvert chez au moins un joueur.
  bool isOpen(int sector) {
    final i = numbers.indexOf(sector);
    return i >= 0 && !closedByAll(i);
  }

  @override
  void onDart(int player, DartThrow d) {
    final i = numbers.indexOf(d.sector);
    if (d.isMiss || i < 0) return;
    var hits = d.multiplier;
    final m = marks[player];
    final need = math.max(0, 3 - m[i]);
    final close = math.min(need, hits);
    m[i] += close;
    hits -= close;
    if (hits > 0) {
      final open = [
        for (var p = 0; p < names.length; p++)
          if (p != player && marks[p][i] < 3) p,
      ];
      if (open.isNotEmpty) {
        switch (variant) {
          case CricketVariant.noScore:
            break;
          case CricketVariant.cutThroat:
            for (final p in open) {
              points[p] += hits * d.sector;
            }
          default:
            points[player] += hits * d.sector;
        }
      }
      m[i] += hits;
    }
    if (m.every((x) => x >= 3)) {
      final others = [
        for (var p = 0; p < names.length; p++)
          if (p != player) points[p],
      ];
      final ahead = lowWins
          ? points[player] <= others.fold<int>(1 << 30, math.min)
          : points[player] >= others.fold<int>(0, math.max);
      if (variant == CricketVariant.noScore || ahead) finish(player);
    }
    // Tout est fermé chez tout le monde : plus personne ne marque, le meilleur score gagne.
    if (!isFinished && Iterable<int>.generate(numbers.length).every(closedByAll)) finishOnBestScore();
  }

  @override
  void finishOnBestScore() {
    if (!lowWins) return super.finishOnBestScore();
    final best = points.fold<int>(1 << 30, math.min);
    winners = [
      for (var i = 0; i < names.length; i++)
        if (points[i] == best) i,
    ];
    winnerIndex = winners.first;
  }
}

// MARK: Around the clock

/// Tour de l'horloge : toucher 1, 2, ... 20 dans l'ordre (simple, double ou triple).
class ClockGame extends TurnGame {
  ClockGame(super.names) {
    resetState();
  }

  late List<int> target;

  @override
  void resetState() => target = List.filled(names.length, 1);

  @override
  int scoreOf(int player) => target[player];

  /// Cibles déjà touchées.
  int done(int player) => target[player] - 1;

  @override
  void onDart(int player, DartThrow d) {
    if (d.sector != target[player]) return;
    target[player]++;
    if (target[player] > 20) {
      target[player] = 20;
      finish(player);
    }
  }
}

// MARK: Shanghai

/// Shanghai : manche n, on vise le n. Simple, double et triple du n au même tour : gagné.
class ShanghaiGame extends TurnGame {
  ShanghaiGame(super.names, {this.rounds = 7}) {
    resetState();
  }

  final int rounds;
  late List<int> points;

  int get target => math.min(round, rounds);

  @override
  void resetState() => points = List.filled(names.length, 0);

  @override
  int scoreOf(int player) => points[player];

  @override
  void onDart(int player, DartThrow d) {
    if (d.sector != target) return;
    points[player] += d.score;
    final t = currentTurn.where((x) => x.sector == target).map((x) => x.multiplier).toSet();
    if (t.containsAll(const [1, 2, 3])) finish(player);
  }

  @override
  void onRoundEnd() {
    if (round > rounds) finishOnBestScore();
  }
}

// MARK: Killer

/// Killer : chacun a un numéro et 3 vies. Ton double te rend killer,
/// puis le double d'un adversaire lui retire une vie. Dernier debout gagne.
class KillerGame extends TurnGame {
  KillerGame(super.names, {List<int>? numbers, this.lives = 3}) : numbers = numbers ?? _draw(names.length) {
    resetState();
  }

  final List<int> numbers;
  final int lives;
  late List<int> life;
  late List<bool> killer;

  /// Dernier événement, pour la bannière ("Max perd une vie. Plus que 1.").
  String? lastEvent;

  static List<int> _draw(int n) => (List.generate(20, (i) => i + 1)..shuffle()).take(n).toList();

  @override
  void resetState() {
    life = List.filled(names.length, lives);
    killer = List.filled(names.length, false);
    lastEvent = null;
  }

  @override
  bool isOut(int player) => life[player] <= 0;

  @override
  int scoreOf(int player) => life[player];

  @override
  void onDart(int player, DartThrow d) {
    if (!d.isDouble) return;
    final owner = numbers.indexOf(d.sector);
    if (owner < 0 || isOut(owner)) return;
    if (owner == player) {
      if (!killer[player]) {
        killer[player] = true;
        lastEvent = '${names[player]} devient killer.';
      } else {
        life[player]--;
        lastEvent = '${names[player]} se tire dessus. Plus que ${life[player]}.';
      }
    } else if (killer[player]) {
      life[owner]--;
      lastEvent = life[owner] > 0
          ? '${names[owner]} perd une vie. Plus que ${life[owner]}.'
          : '${names[owner]} est éliminé.';
    }
    final alive = [
      for (var i = 0; i < names.length; i++)
        if (!isOut(i)) i,
    ];
    if (names.length > 1 && alive.length == 1) finish(alive.single);
    if (names.length == 1 && isOut(player)) finish(player);
  }
}

// MARK: Halve-it

/// Une cible de Halve-it : un numéro, les doubles, les triples ou le bull.
class HalveTarget {
  const HalveTarget(this.label, this.matches);
  final String label;
  final bool Function(DartThrow) matches;

  static final standard = [
    HalveTarget('19', (d) => d.sector == 19),
    HalveTarget('18', (d) => d.sector == 18),
    HalveTarget('17', (d) => d.sector == 17),
    HalveTarget('Doubles', (d) => d.isDouble),
    HalveTarget('16', (d) => d.sector == 16),
    HalveTarget('Triples', (d) => d.multiplier == 3),
    HalveTarget('15', (d) => d.sector == 15),
    HalveTarget('20', (d) => d.sector == 20),
    HalveTarget('Bull', (d) => d.sector == 25),
  ];

  /// Bermuda : 12 manches, de 12 à 20 avec un double, un triple et le bull.
  static final bermuda = [
    for (final n in [12, 13, 14]) HalveTarget('$n', (d) => d.sector == n),
    HalveTarget('Double', (d) => d.isDouble),
    for (final n in [15, 16, 17]) HalveTarget('$n', (d) => d.sector == n),
    HalveTarget('Triple', (d) => d.multiplier == 3),
    for (final n in [18, 19, 20]) HalveTarget('$n', (d) => d.sector == n),
    HalveTarget('Bull', (d) => d.sector == 25),
  ];
}

/// Halve-it : 9 manches avec une cible imposée. Rien touché au tour : ton score est divisé par deux.
class HalveItGame extends TurnGame {
  HalveItGame(super.names, {this.start = 40, List<HalveTarget>? targets}) : targets = targets ?? HalveTarget.standard {
    resetState();
  }

  /// Bermuda : mêmes règles, 12 manches, départ à 0.
  HalveItGame.bermuda(List<String> names) : this(names, start: 0, targets: HalveTarget.bermuda);

  final int start;
  final List<HalveTarget> targets;
  late List<int> points;
  late List<int> halves;

  HalveTarget get target => targets[math.min(round, targets.length) - 1];

  @override
  void resetState() {
    points = List.filled(names.length, start);
    halves = List.filled(names.length, 0);
  }

  @override
  int scoreOf(int player) => points[player];

  @override
  void onDart(int player, DartThrow d) {
    if (target.matches(d)) points[player] += d.score;
  }

  @override
  void onTurnEnd(int player, List<DartThrow> turn) {
    if (!turn.any(target.matches)) {
      points[player] = points[player] ~/ 2;
      halves[player]++;
    }
  }

  @override
  void onRoundEnd() {
    if (round > targets.length) finishOnBestScore();
  }
}

// MARK: Bob's 27

/// Bob's 27 : départ à 27, on vise D1 à D20 puis le bull. Chaque double touché rapporte sa valeur,
/// un tour sans double coûte la valeur du double. Sous zéro : éliminé.
class Bobs27Game extends TurnGame {
  Bobs27Game(super.names) {
    resetState();
  }

  static const rounds = 21;
  late List<int> points;

  /// Gain ou perte du dernier tour de chaque joueur.
  late List<int?> lastDelta;

  /// Secteur du double visé (25 pour le bull).
  int get target => round >= rounds ? 25 : round;

  @override
  void resetState() {
    points = List.filled(names.length, 27);
    lastDelta = List.filled(names.length, null);
  }

  @override
  bool isOut(int player) => points[player] < 0;

  @override
  int scoreOf(int player) => points[player];

  @override
  void onDart(int player, DartThrow d) {
    if (d.isDouble && d.sector == target) points[player] += d.score;
  }

  @override
  void onTurnEnd(int player, List<DartThrow> turn) {
    final hit = turn.where((d) => d.isDouble && d.sector == target).fold<int>(0, (n, d) => n + d.score);
    if (hit == 0) points[player] -= target * 2;
    lastDelta[player] = hit == 0 ? -target * 2 : hit;
    final alive = [
      for (var i = 0; i < names.length; i++)
        if (!isOut(i)) i,
    ];
    if (alive.isEmpty) {
      finishOnBestScore();
    } else if (names.length > 1 && alive.length == 1 && isOut(player)) {
      finish(alive.single);
    }
  }

  @override
  void onRoundEnd() {
    if (round > rounds) finishOnBestScore();
  }
}

// MARK: Gotcha

/// Gotcha : premier à 301 pile. Tomber sur le score d'un adversaire le renvoie à 0.
/// Dépasser 301 : bust, retour au score du début du tour.
class GotchaGame extends TurnGame {
  GotchaGame(super.names, {this.goal = 301}) {
    resetState();
  }

  final int goal;
  late List<int> points;
  int _turnStart = 0;

  /// Dernier Gotcha, pour l'alerte ("Gotcha. Max retourne à 0.").
  String? lastEvent;

  /// Nombre de Gotcha réussis par joueur.
  late List<int> gotchas;

  /// Le dernier tour a busté.
  bool busted = false;

  @override
  void resetState() {
    points = List.filled(names.length, 0);
    gotchas = List.filled(names.length, 0);
    _turnStart = 0;
    lastEvent = null;
    busted = false;
  }

  @override
  int scoreOf(int player) => points[player];

  /// Reste à faire pour finir.
  int left(int player) => goal - points[player];

  @override
  void onDart(int player, DartThrow d) {
    if (currentTurn.length == 1) {
      _turnStart = points[player];
      busted = false;
    }
    final next = points[player] + d.score;
    if (next > goal) {
      points[player] = _turnStart;
      busted = true;
      endTurn();
      return;
    }
    points[player] = next;
    if (next == goal) return finish(player);
    if (d.isMiss || d.score == 0) return;
    for (var p = 0; p < names.length; p++) {
      if (p != player && points[p] == next && next > 0) {
        points[p] = 0;
        gotchas[player]++;
        lastEvent = 'Gotcha. ${names[p]} retourne à 0.';
      }
    }
  }
}
