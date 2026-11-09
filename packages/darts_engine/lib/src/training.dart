import 'dart_throw.dart';
import 'modes.dart';

/// Cible d'une série d'entraînement : un segment précis, ou le bull (25 et 50 comptent).
class TrainingTarget {
  const TrainingTarget(this.sector, this.multiplier);

  static const bull = TrainingTarget(25, 0);

  /// Cibles proposées sur l'écran "Choisis ton jeu".
  static const presets = [
    TrainingTarget(20, 3),
    TrainingTarget(19, 3),
    TrainingTarget(18, 3),
    TrainingTarget(20, 2),
    TrainingTarget(16, 2),
    bull,
  ];

  final int sector;

  /// 1, 2 ou 3. 0 pour le bull, où simple et double comptent.
  final int multiplier;

  bool matches(DartThrow d) => !d.isMiss && d.sector == sector && (multiplier == 0 || d.multiplier == multiplier);

  /// "T20", "D16", "Bull".
  String get label => sector == 25 ? 'Bull' : '${const ['S', 'D', 'T'][multiplier - 1]}$sector';

  /// "Triples 20", "Doubles 16", "Bulls".
  String get plural => sector == 25 ? 'Bulls' : '${const ['Simples', 'Doubles', 'Triples'][multiplier - 1]} $sector';

  /// Clé stable pour l'historique : "T20", "D16", "BULL".
  String get key => sector == 25 ? 'BULL' : label;

  static TrainingTarget? fromKey(String key) => presets.where((t) => t.key == key).firstOrNull;

  @override
  bool operator ==(Object other) => other is TrainingTarget && other.sector == sector && other.multiplier == multiplier;

  @override
  int get hashCode => Object.hash(sector, multiplier);
}

/// Série libre : un joueur, une cible, un nombre fixe de fléchettes, par volées de 3.
class TrainingGame extends TurnGame {
  TrainingGame(String name, {required this.target, this.darts = 15})
    : assert(darts > 0),
      super([name]);

  final TrainingTarget target;

  /// Fléchettes dans la série.
  final int darts;

  int thrown = 0;
  int hits = 0;
  int streak = 0;
  int bestStreak = 0;

  /// Réussite en pour cent, 0 avant la première fléchette.
  int get rate => thrown == 0 ? 0 : (hits * 100 / thrown).round();

  @override
  int scoreOf(int player) => hits;

  @override
  void resetState() {
    thrown = 0;
    hits = 0;
    streak = 0;
    bestStreak = 0;
  }

  @override
  void onDart(int player, DartThrow d) {
    thrown++;
    if (target.matches(d)) {
      hits++;
      streak++;
      if (streak > bestStreak) bestStreak = streak;
    } else {
      streak = 0;
    }
    if (thrown >= darts) finish(player);
  }
}

/// Volées libres : un joueur tire des volées de 3, n'importe où. On compte les points.
class VolleyGame extends TurnGame {
  /// [volleys] à 0 : sans fin, on arrête quand on veut.
  VolleyGame(String name, {this.volleys = 10})
    : assert(volleys >= 0),
      super([name]);

  final int volleys;

  int done = 0;
  int total = 0;
  int dartsThrown = 0;
  int best = 0;
  int ton = 0;
  int ton40 = 0;
  int max180 = 0;

  /// Scores des volées finies, dans l'ordre.
  final List<int> scores = [];

  /// Moyenne sur 3 fléchettes, 0 avant la première.
  double get average => dartsThrown == 0 ? 0 : total * 3 / dartsThrown;

  /// Points de la volée en cours.
  int get current => currentTurn.fold(0, (n, d) => n + d.score);

  @override
  int scoreOf(int player) => total;

  @override
  void resetState() {
    done = 0;
    total = 0;
    dartsThrown = 0;
    best = 0;
    ton = 0;
    ton40 = 0;
    max180 = 0;
    scores.clear();
  }

  @override
  void onDart(int player, DartThrow d) {
    dartsThrown++;
    total += d.score;
    if (currentTurn.length == 3) _volley(player, current);
  }

  /// Volée arrêtée avant 3 fléchettes : elle compte quand même.
  @override
  void onTurnEnd(int player, List<DartThrow> turn) {
    if (turn.isNotEmpty && turn.length < 3) _volley(player, turn.fold(0, (n, d) => n + d.score));
  }

  void _volley(int player, int score) {
    done++;
    scores.add(score);
    if (score > best) best = score;
    if (score == 180) {
      max180++;
    } else if (score >= 140) {
      ton40++;
    } else if (score >= 100) {
      ton++;
    }
    if (volleys > 0 && done >= volleys) finish(player);
  }
}
