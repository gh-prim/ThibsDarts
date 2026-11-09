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
