import 'dart:math' as math;

import 'checkout.dart';
import 'dart_throw.dart';
import 'modes.dart';

/// Résultat d'une fléchette pour une sortie (X01 en double out).
enum _Out { scored, bust, checkout }

_Out _applyOut(int remaining, DartThrow d) {
  final left = remaining - d.score;
  if (left < 0 || left == 1 || (left == 0 && !d.isDouble)) return _Out.bust;
  return left == 0 ? _Out.checkout : _Out.scored;
}

// MARK: Échelle de sorties (Catch 40, 41-60)

/// Finir chaque score de [from] à [to] en double out, [dartsPer] fléchettes max par score.
/// Points par score réussi selon les fléchettes utilisées ([pointsFor]).
class LadderGame extends TurnGame {
  LadderGame(String name, {required this.from, required this.to, required this.dartsPer, required this.pointsFor})
    : assert(to >= from),
      super([name]) {
    resetState();
  }

  /// Catch 40 : 61 à 100, 6 fléchettes, 3 points en 3 fléchettes ou moins, 2 points en 4 à 6.
  LadderGame.catch40(String name) : this(name, from: 61, to: 100, dartsPer: 6, pointsFor: (n) => n <= 3 ? 3 : 2);

  /// 41-60 : 3 fléchettes par score, 1 point par score fini.
  LadderGame.fortyOne(String name) : this(name, from: 41, to: 60, dartsPer: 3, pointsFor: (_) => 1);

  final int from;
  final int to;
  final int dartsPer;
  final int Function(int darts) pointsFor;

  /// Score à finir en ce moment.
  int get target => from + results.length;

  /// Reste à faire sur le score en cours.
  late int remaining;

  /// Fléchettes déjà lancées sur le score en cours.
  late int dartsUsed;
  late int _volleyStart;

  /// Points gagnés par score, dans l'ordre (0 si raté).
  final List<int> results = [];

  int total = 0;

  int get count => to - from + 1;
  int get dartsLeft => dartsPer - dartsUsed;
  int get successes => results.where((r) => r > 0).length;

  /// Réussite en pour cent sur les scores joués.
  int get rate => results.isEmpty ? 0 : (successes * 100 / results.length).round();

  List<DartThrow>? get hint => isFinished ? null : suggestCheckout(remaining, dartsLeft: math.min(3, dartsLeft));

  @override
  int scoreOf(int player) => total;

  @override
  void resetState() {
    results.clear();
    total = 0;
    remaining = from;
    _volleyStart = from;
    dartsUsed = 0;
  }

  void _next(int points) {
    results.add(points);
    total += points;
    dartsUsed = 0;
    if (results.length >= count) {
      finish(0);
      return;
    }
    remaining = target;
    _volleyStart = remaining;
  }

  @override
  void onDart(int player, DartThrow d) {
    dartsUsed++;
    switch (_applyOut(remaining, d)) {
      case _Out.checkout:
        _next(pointsFor(dartsUsed));
        endTurn();
      case _Out.bust:
        remaining = _volleyStart;
        dartsUsed = ((dartsUsed + 2) ~/ 3) * 3;
        if (dartsUsed >= dartsPer) _next(0);
        endTurn();
      case _Out.scored:
        remaining -= d.score;
        if (dartsUsed >= dartsPer) _next(0);
    }
  }

  @override
  void onTurnEnd(int player, List<DartThrow> turn) => _volleyStart = remaining;
}

// MARK: Sorties en 9 fléchettes (9 Darts Double Out, 170, Checkout au hasard)

/// Plage de scores du Checkout au hasard.
enum CheckoutRange {
  small(2, 60, 'Petits'),
  medium(61, 120, 'Moyens'),
  big(121, 170, 'Gros'),
  all(2, 170, 'Tous');

  const CheckoutRange(this.from, this.to, this.label);
  final int from;
  final int to;
  final String label;
}

/// Une suite de tentatives : finir un score en double out en [maxDarts] fléchettes.
/// Raté (fléchettes épuisées) : tentative suivante.
class CheckoutDrill extends TurnGame {
  CheckoutDrill(String name, {required this.targets, this.maxDarts = 9}) : assert(targets.isNotEmpty), super([name]) {
    resetState();
  }

  /// 9 Darts Double Out : finir [start] (121 ou 81) en 9 fléchettes.
  CheckoutDrill.nineDarts(String name, {int start = 121, int attempts = 10})
    : this(name, targets: List.filled(attempts, start));

  /// 170 : partir de 170, 9 fléchettes max.
  CheckoutDrill.ton70(String name, {int attempts = 10}) : this(name, targets: List.filled(attempts, 170));

  /// Checkout au hasard : un score tiré dans [range], 3 volées pour finir.
  factory CheckoutDrill.random(String name, {CheckoutRange range = CheckoutRange.all, int attempts = 10, math.Random? random}) {
    final r = random ?? math.Random();
    final ok = [
      for (var n = range.from; n <= range.to; n++)
        if (suggestCheckout(n) != null) n,
    ];
    return CheckoutDrill(name, targets: [for (var i = 0; i < attempts; i++) ok[r.nextInt(ok.length)]]);
  }

  final List<int> targets;
  final int maxDarts;

  /// Réussite (true) ou échec de chaque tentative finie.
  final List<bool> results = [];

  /// Fléchettes utilisées pour chaque sortie réussie.
  final List<int> dartsToFinish = [];

  late int remaining;
  late int dartsUsed;
  late int _volleyStart;
  int streak = 0;
  int bestStreak = 0;

  int get attempt => math.min(results.length + 1, targets.length);
  int get attempts => targets.length;
  int get target => targets[math.min(results.length, targets.length - 1)];
  int get successes => results.where((r) => r).length;
  int get dartsLeft => maxDarts - dartsUsed;

  /// Volée en cours sur la tentative (1 à 3).
  int get volley => dartsUsed ~/ 3 + 1;

  int get rate => results.isEmpty ? 0 : (successes * 100 / results.length).round();

  /// Dernière tentative finie : réussie, ratée, ou null.
  bool? get lastResult => results.isEmpty ? null : results.last;

  List<DartThrow>? get hint => isFinished ? null : suggestCheckout(remaining, dartsLeft: math.min(3, dartsLeft));

  @override
  int scoreOf(int player) => successes;

  @override
  void resetState() {
    results.clear();
    dartsToFinish.clear();
    streak = 0;
    bestStreak = 0;
    dartsUsed = 0;
    remaining = targets.first;
    _volleyStart = remaining;
  }

  void _next(bool ok) {
    results.add(ok);
    if (ok) {
      dartsToFinish.add(dartsUsed);
      streak++;
      bestStreak = math.max(bestStreak, streak);
    } else {
      streak = 0;
    }
    dartsUsed = 0;
    if (results.length >= targets.length) {
      finish(0);
      return;
    }
    remaining = target;
    _volleyStart = remaining;
  }

  @override
  void onDart(int player, DartThrow d) {
    dartsUsed++;
    switch (_applyOut(remaining, d)) {
      case _Out.checkout:
        remaining = 0;
        _next(true);
        endTurn();
      case _Out.bust:
        remaining = _volleyStart;
        dartsUsed = ((dartsUsed + 2) ~/ 3) * 3;
        if (dartsUsed >= maxDarts) _next(false);
        endTurn();
      case _Out.scored:
        remaining -= d.score;
        if (dartsUsed >= maxDarts) _next(false);
    }
  }

  @override
  void onTurnEnd(int player, List<DartThrow> turn) => _volleyStart = remaining;
}

// MARK: JDC Challenge

/// JDC Challenge : Shanghai de 10 à 15, puis une fléchette par double (1 à 20 et bull, 50 points),
/// puis Shanghai de 15 à 20. Simple, double et triple en une volée : bonus de 100.
class JdcGame extends TurnGame {
  JdcGame(String name) : super([name]) {
    resetState();
  }

  /// 6 volées de Shanghai, 21 doubles, 6 volées de Shanghai.
  static const steps = 33;
  static const bonus = 100;

  /// Manche en cours, de 0 à 32.
  late int step;
  int total = 0;
  int shanghais = 0;
  int doubles = 0;
  bool _doublesTurn = false;

  /// Points par phase.
  final List<int> phasePoints = [0, 0, 0];

  /// Phase en cours : 1, 2 ou 3.
  int get phase => step < 6 ? 1 : step < 27 ? 2 : 3;

  /// Secteur visé (25 pour le bull).
  int get target => targetAt(step);

  static int targetAt(int s) => s < 6 ? 10 + s : s < 26 ? s - 5 : s == 26 ? 25 : 15 + (s - 27);

  @override
  int scoreOf(int player) => total;

  @override
  void resetState() {
    step = 0;
    total = 0;
    _doublesTurn = false;
    shanghais = 0;
    doubles = 0;
    phasePoints.setAll(0, [0, 0, 0]);
  }

  void _add(int n) {
    total += n;
    phasePoints[phase - 1] += n;
  }

  @override
  void onDart(int player, DartThrow d) {
    if (currentTurn.length == 1) _doublesTurn = phase == 2;
    if (phase == 2) {
      if (d.isDouble && d.sector == target) {
        _add(50);
        doubles++;
      }
      step++;
      if (step == 27 && currentTurn.length < 3) endTurn();
      return;
    }
    if (d.sector == target) _add(d.score);
  }

  @override
  void onTurnEnd(int player, List<DartThrow> turn) {
    if (_doublesTurn) {
      _doublesTurn = false;
      return;
    }
    final m = turn.where((d) => d.sector == target).map((d) => d.multiplier).toSet();
    if (m.containsAll(const [1, 2, 3])) {
      _add(bonus);
      shanghais++;
    }
    step++;
    if (step >= steps) finish(0);
  }
}

// MARK: 99 fléchettes

/// 99 fléchettes sur une cible : 33 volées sur le même numéro. Seules les touches sur la cible comptent.
class Darts99Game extends TurnGame {
  Darts99Game(String name, {this.sector = 20, this.volleys = 33}) : super([name]) {
    resetState();
  }

  final int sector;
  final int volleys;

  int total = 0;
  int thrown = 0;

  /// Touches en simple, double, triple.
  final List<int> counts = [0, 0, 0];
  final List<int> scores = [];

  int get volley => math.min(scores.length + 1, volleys);
  int get hits => counts.fold(0, (a, b) => a + b);

  /// Moyenne par volée.
  double get average => thrown == 0 ? 0 : total * 3 / thrown;

  @override
  int scoreOf(int player) => total;

  @override
  void resetState() {
    total = 0;
    thrown = 0;
    counts.setAll(0, [0, 0, 0]);
    scores.clear();
  }

  @override
  void onDart(int player, DartThrow d) {
    thrown++;
    if (d.sector != sector) return;
    total += d.score;
    counts[d.multiplier - 1]++;
  }

  @override
  void onTurnEnd(int player, List<DartThrow> turn) {
    scores.add(turn.where((d) => d.sector == sector).fold(0, (n, d) => n + d.score));
    if (scores.length >= volleys) finish(0);
  }
}

// MARK: Tour du monde

/// Tour du monde : 1 à 20 puis le bull, une volée par numéro, touché ou pas.
/// [multiplier] 1 : tout le numéro compte. 2 : seulement les doubles. 3 : seulement les triples (bull : 50).
class RoundTheWorldGame extends TurnGame {
  RoundTheWorldGame(String name, {this.multiplier = 1}) : super([name]) {
    resetState();
  }

  static const sectors = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 25];

  final int multiplier;
  int total = 0;

  /// Points par numéro joué.
  final List<int> points = [];

  int get target => sectors[math.min(points.length, sectors.length - 1)];

  bool counts(DartThrow d) {
    if (d.sector != target) return false;
    if (multiplier == 1) return true;
    if (d.sector == 25) return d.multiplier == 2;
    return d.multiplier == multiplier;
  }

  /// Points de la volée en cours.
  int get current => currentTurn.where(counts).fold(0, (n, d) => n + d.score);

  @override
  int scoreOf(int player) => total;

  @override
  void resetState() {
    total = 0;
    points.clear();
  }

  @override
  void onDart(int player, DartThrow d) {
    if (counts(d)) total += d.score;
  }

  @override
  void onTurnEnd(int player, List<DartThrow> turn) {
    points.add(turn.where(counts).fold(0, (n, d) => n + d.score));
    if (points.length >= sectors.length) finish(0);
  }
}

// MARK: Cricket Count Up

/// Cricket Count Up : 8 volées, on compte les marques sur 15 à 20 et le bull.
class CricketCountUpGame extends TurnGame {
  CricketCountUpGame(String name, {this.volleys = 8}) : super([name]) {
    resetState();
  }

  final int volleys;
  int total = 0;

  /// Marques par numéro, dans l'ordre de [CricketGame.standard].
  final List<int> marks = List.filled(CricketGame.standard.length, 0);
  final List<int> perVolley = [];

  int get volley => math.min(perVolley.length + 1, volleys);

  /// Marques par volée en moyenne.
  double get average => perVolley.isEmpty ? 0 : perVolley.fold(0, (a, b) => a + b) / perVolley.length;

  static int marksOf(DartThrow d) => CricketGame.standard.contains(d.sector) ? d.multiplier : 0;

  @override
  int scoreOf(int player) => total;

  @override
  void resetState() {
    total = 0;
    marks.fillRange(0, marks.length, 0);
    perVolley.clear();
  }

  @override
  void onDart(int player, DartThrow d) {
    final m = marksOf(d);
    if (m == 0) return;
    total += m;
    marks[CricketGame.standard.indexOf(d.sector)] += m;
  }

  @override
  void onTurnEnd(int player, List<DartThrow> turn) {
    perVolley.add(turn.fold(0, (n, d) => n + marksOf(d)));
    if (perVolley.length >= volleys) finish(0);
  }
}
