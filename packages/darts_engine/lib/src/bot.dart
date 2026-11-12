import 'dart:math' as math;

import 'checkout.dart';
import 'dart_throw.dart';
import 'modes.dart';

/// Un niveau du robot : son nom et sa moyenne visée sur 3 fléchettes.
class BotLevel {
  const BotLevel(this.average, this.name);
  final int average;
  final String name;

  static const all = [
    BotLevel(30, 'Touriste'),
    BotLevel(45, 'Du dimanche'),
    BotLevel(60, 'Habitué'),
    BotLevel(75, 'Régulier'),
    BotLevel(90, 'Costaud'),
    BotLevel(105, 'Pro'),
  ];

  static BotLevel of(int average) => all.firstWhere((l) => l.average == average, orElse: () => all[2]);

  /// Niveau au-dessus ou en dessous, null au bout de la jauge.
  BotLevel? get up => all.indexOf(this) < all.length - 1 ? all[all.indexOf(this) + 1] : null;
  BotLevel? get down => all.indexOf(this) > 0 ? all[all.indexOf(this) - 1] : null;
}

/// Robot adversaire : il vise comme un joueur et rate comme un humain.
///
/// Chaque fléchette part vers le centre du segment visé avec un écart aléatoire (loi normale).
/// L'écart dépend du niveau, réglé pour que la moyenne en visant le T20 colle au niveau.
class DartBot {
  DartBot(this.level, {math.Random? random}) : _random = random ?? math.Random(), sigma = sigmaFor(level.average);

  final BotLevel level;
  final double sigma;
  final math.Random _random;

  /// Ordre des secteurs dans le sens des aiguilles d'une montre, 20 en haut.
  static const order = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5];

  // Rayons de la cible en mm.
  static const _bull = 6.35, _outer = 15.9, _tripleIn = 99.0, _tripleOut = 107.0, _doubleIn = 162.0, _doubleOut = 170.0;

  /// Écart type (mm) par moyenne visée, mesuré par simulation en visant le T20.
  static const _table = [(30, 63.0), (45, 25.0), (60, 16.6), (75, 12.5), (90, 9.8), (105, 7.6)];

  static double sigmaFor(int average) {
    if (average <= _table.first.$1) return _table.first.$2;
    for (var i = 1; i < _table.length; i++) {
      final (a1, s1) = _table[i];
      if (average <= a1) {
        final (a0, s0) = _table[i - 1];
        return s0 + (s1 - s0) * (average - a0) / (a1 - a0);
      }
    }
    return _table.last.$2;
  }

  /// Segment touché aux coordonnées (mm, y vers le haut).
  static DartThrow hitAt(double x, double y) {
    final r = math.sqrt(x * x + y * y);
    if (r <= _bull) return DartThrow.bull;
    if (r <= _outer) return DartThrow.outerBull;
    if (r > _doubleOut) return const DartThrow.miss();
    final deg = (90 - math.atan2(y, x) * 180 / math.pi + 9) % 360;
    final sector = order[(deg ~/ 18) % 20];
    if (r >= _doubleIn) return DartThrow.double(sector);
    if (r >= _tripleIn && r <= _tripleOut) return DartThrow.triple(sector);
    return DartThrow.single(sector);
  }

  /// Point visé pour un segment.
  static (double, double) aimPoint(DartThrow aim) {
    if (aim.sector == 25) return (0, 0);
    final r = switch (aim.multiplier) {
      3 => (_tripleIn + _tripleOut) / 2,
      2 => (_doubleIn + _doubleOut) / 2,
      _ => (_tripleOut + _doubleIn) / 2,
    };
    final a = (90 - order.indexOf(aim.sector) * 18) * math.pi / 180;
    return (r * math.cos(a), r * math.sin(a));
  }

  double _gauss() {
    final u = 1 - _random.nextDouble();
    final v = _random.nextDouble();
    return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v);
  }

  /// Lance une fléchette vers [aim].
  DartThrow throwAt(DartThrow aim) {
    final (x, y) = aimPoint(aim);
    return hitAt(x + _gauss() * sigma, y + _gauss() * sigma);
  }

  /// Cible en X01 : la sortie si elle existe, sinon le T20 ou un placement.
  static DartThrow aimX01(int remaining, {int dartsLeft = 3, bool doubleOut = true}) {
    if (!doubleOut) {
      if (remaining > 60) return const DartThrow.triple(20);
      if (remaining <= 20) return DartThrow.single(remaining);
      if (remaining == 25 || remaining == 50) return remaining == 50 ? DartThrow.bull : DartThrow.outerBull;
      for (final m in [3, 2]) {
        if (remaining % m == 0 && remaining ~/ m <= 20) return DartThrow(remaining ~/ m, m);
      }
      return const DartThrow.single(20);
    }
    final route = suggestCheckout(remaining, dartsLeft: dartsLeft);
    if (route != null) return route.first;
    if (remaining > 100) return const DartThrow.triple(20);
    // Placer un double propre : 32, 40, 16...
    for (final keep in const [32, 40, 16, 24, 36, 20, 8, 4, 2]) {
      final s = remaining - keep;
      if (s >= 1 && s <= 20) return DartThrow.single(s);
      if (s > 20 && s <= 60 && s % 3 == 0) return DartThrow.triple(s ~/ 3);
    }
    return remaining > 60 ? const DartThrow.triple(20) : const DartThrow.single(1);
  }

  /// Cible au Cricket pour le joueur [me] : marquer si on est derrière, sinon fermer.
  static DartThrow aimCricket(CricketGame g, int me) {
    DartThrow t(int sector) => sector == 25 ? DartThrow.bull : DartThrow.triple(sector);
    final open = [
      for (var i = 0; i < g.numbers.length; i++)
        if (g.marks[me][i] < 3 && !g.closedByAll(i)) i,
    ];
    final scoring = g.variant == CricketVariant.noScore
        ? <int>[]
        : [
            for (var i = 0; i < g.numbers.length; i++)
              if (g.marks[me][i] >= 3 && !g.closedByAll(i)) i,
          ];
    final others = [
      for (var p = 0; p < g.names.length; p++)
        if (p != me) g.points[p],
    ];
    final behind = g.lowWins
        ? g.points[me] > others.fold<int>(1 << 30, math.min)
        : g.points[me] < others.fold<int>(0, math.max);
    if (behind && scoring.isNotEmpty && !g.lowWins) return t(g.numbers[scoring.first]);
    if (open.isNotEmpty) return t(g.numbers[open.first]);
    if (scoring.isNotEmpty && !g.lowWins) return t(g.numbers[scoring.first]);
    return const DartThrow.triple(20);
  }
}
