import 'dart:math' as math;

import 'checkout.dart';
import 'dart_throw.dart';
import 'modes.dart';

// Coach adaptatif des check-out.
//
// Tout ce que le coach sait vient des fléchettes : double visé, fléchette, position exacte (mm).
// Chaque niveau (zone de chaque double, sorties, pression) bouge après chaque essai :
// +0,4 sur une réussite, -0,6 sur un raté. Il se stabilise donc là où on réussit 60 % du temps.

const _upStep = 0.4, _downStep = 0.6;

/// Niveau suivant après une réussite ou un raté (escalier à 60 %).
double coachStep(double level, bool ok, {double max = 3}) =>
    (level + (ok ? _upStep : -_downStep)).clamp(0.0, max).toDouble();

/// Ordre des secteurs, du haut, sens horaire.
const _order = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5];

/// Rayon du milieu des doubles (mm).
const doubleMidRadius = 166.0;

/// Les 21 doubles, D20 à D1 puis bull.
final List<DartThrow> coachDoubles = [for (var s = 20; s >= 1; s--) DartThrow.double(s), DartThrow.bull];

/// Fréquence des doubles en fin de manche : les plus joués comptent plus.
double _weight(DartThrow d) => switch (d.sector) {
  20 || 16 || 18 || 12 || 10 || 8 => 1.0,
  14 || 6 || 4 || 2 || 25 => 0.8,
  _ => 0.55,
};

/// Écart d'une fléchette au milieu de la case visée (mm) : radial (+ vers l'extérieur)
/// et tangentiel (+ dans le sens horaire). Position en mm, centre (0, 0), y vers le bas.
({double radial, double tangential}) aimError(DartThrow aim, double x, double y) {
  if (aim.sector == 25 || aim.isMiss) return (radial: -y, tangential: x);
  final r = math.sqrt(x * x + y * y);
  final mid = _order.indexOf(aim.sector) * 18.0;
  var a = math.atan2(x, -y) * 180 / math.pi;
  var diff = a - mid;
  while (diff > 180) {
    diff -= 360;
  }
  while (diff < -180) {
    diff += 360;
  }
  a = diff;
  final rMid = aim.multiplier == 3
      ? 103.0
      : aim.multiplier == 2
      ? doubleMidRadius
      : 135.0;
  return (radial: r - rMid, tangential: r * a * math.pi / 180);
}

/// Part du double éclairée au niveau [level] (0 à 3) : 100 % à 0, 25 % à 3.
double zoneFraction(double level) => math.pow(0.25, level.clamp(0, 3) / 3).toDouble();

/// La fléchette [d] tombe dans la zone : la bonne case, et au plus [fraction] de sa largeur
/// autour du milieu (le bull compte en entier).
bool inZone(DartThrow aim, DartThrow d, double? x, double? y, double fraction) {
  if (d != aim) return false;
  if (aim.sector == 25 || x == null || y == null || fraction >= 0.999) return true;
  final e = aimError(aim, x, y);
  final half = doubleMidRadius * 9 * math.pi / 180 * fraction;
  return e.tangential.abs() <= half;
}

/// Un essai sur un double : visé, touché (la case), position si connue.
class DoubleTry {
  const DoubleTry(this.aim, this.hit, {this.x, this.y});
  final DartThrow aim;
  final bool hit;
  final double? x, y;
}

/// Un check-out tenté : score de départ et réussite.
class CheckoutTry {
  const CheckoutTry(this.score, this.ok);
  final int score;
  final bool ok;
}

/// Ce que le coach sait d'un double.
class DoubleSkill {
  DoubleSkill(this.target);
  final DartThrow target;
  int attempts = 0;
  int hits = 0;

  /// Écart moyen des fléchettes (mm), sur les essais avec position.
  double radial = 0, tangential = 0;
  int placed = 0;

  /// Réussite estimée (0 à 1) : les 40 derniers essais, avec un a priori de 30 % pour 5 essais.
  double get rate => (hits + 1.5) / (attempts + 5);

  /// Réussite brute (0 à 100), null sans essai.
  int? get pct => attempts == 0 ? null : (hits * 100 / attempts).round();

  /// Faiblesse : plus c'est haut, plus le coach le travaille.
  double get weakness => (1 - rate) * _weight(target);

  String get label => target.label;
}

/// Tous les niveaux du coach pour un joueur. Repris à la séance suivante.
class CoachLevels {
  CoachLevels({Map<String, double>? zones, this.checkout = 0, this.pressure = 0}) : zones = zones ?? {};

  /// Zone de chaque double (0 à 3), "D16" -> 1,2.
  final Map<String, double> zones;

  /// Sorties : 0 (2 à 40) à 6 (141 à 170).
  double checkout;

  /// Pression : 0 (3 volées avant le fantôme) à 2 (1 volée).
  double pressure;

  double zone(DartThrow d) => zones[d.label] ?? 0;

  CoachLevels copy() => CoachLevels(zones: Map.of(zones), checkout: checkout, pressure: pressure);

  Map<String, Object?> toJson() => {
    'zones': {for (final e in zones.entries) e.key: double.parse(e.value.toStringAsFixed(2))},
    'checkout': double.parse(checkout.toStringAsFixed(2)),
    'pressure': double.parse(pressure.toStringAsFixed(2)),
  };

  factory CoachLevels.fromJson(Map<String, Object?>? j) {
    if (j == null) return CoachLevels();
    final z = j['zones'];
    return CoachLevels(
      zones: {
        if (z is Map)
          for (final e in z.entries)
            if (e.value is num) '${e.key}': (e.value as num).toDouble(),
      },
      checkout: (j['checkout'] as num?)?.toDouble() ?? 0,
      pressure: (j['pressure'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Plages de sortie par niveau.
const checkoutRanges = [(2, 40), (41, 60), (61, 80), (81, 100), (101, 120), (121, 140), (141, 170)];

/// Profil d'un joueur : chaque double, les sorties ratées, les niveaux.
class CoachProfile {
  CoachProfile({List<DoubleTry> tries = const [], List<CheckoutTry> checkouts = const [], CoachLevels? levels})
    : levels = levels ?? CoachLevels() {
    for (final d in coachDoubles) {
      skills[d.label] = DoubleSkill(d);
    }
    // Les 40 derniers essais de chaque double (la liste va du plus ancien au plus récent).
    final per = <String, List<DoubleTry>>{};
    for (final t in tries) {
      if (!t.aim.isDouble) continue;
      per.putIfAbsent(t.aim.label, () => []).add(t);
    }
    for (final e in per.entries) {
      final s = skills[e.key];
      if (s == null) continue;
      final last = e.value.length > 40 ? e.value.sublist(e.value.length - 40) : e.value;
      for (final t in last) {
        s.attempts++;
        if (t.hit) s.hits++;
        if (t.x != null && t.y != null) {
          final err = aimError(t.aim, t.x!, t.y!);
          s.radial += err.radial;
          s.tangential += err.tangential;
          s.placed++;
        }
      }
      if (s.placed > 0) {
        s.radial /= s.placed;
        s.tangential /= s.placed;
      }
    }
    for (final c in checkouts) {
      final k = missed[c.score] ?? 0;
      missed[c.score] = c.ok ? math.max(0, k - 1) : k + 1;
    }
    missed.removeWhere((_, v) => v <= 0);
  }

  final Map<String, DoubleSkill> skills = {};

  /// Sorties ratées plus souvent que réussies : score -> ratés en trop.
  final Map<int, int> missed = {};
  final CoachLevels levels;

  /// Doubles du plus faible au plus fort (fréquence de jeu comprise).
  List<DoubleSkill> get weakest => skills.values.toList()..sort((a, b) => b.weakness.compareTo(a.weakness));

  /// Double "acquis" pour la pression : au moins 15 essais et 45 % de réussite. Sinon le meilleur.
  DoubleSkill get acquired {
    double value(DoubleSkill s) => s.rate * _weight(s.target);
    final ok = skills.values.where((s) => s.attempts >= 15 && s.hits / s.attempts >= 0.45).toList()
      ..sort((a, b) => value(b).compareTo(value(a)));
    if (ok.isNotEmpty) return ok.first;
    final all = skills.values.where((s) => _weight(s.target) >= 1).toList()..sort((a, b) => b.rate.compareTo(a.rate));
    return all.first;
  }

  int get attempts => skills.values.fold(0, (n, s) => n + s.attempts);
  int get hits => skills.values.fold(0, (n, s) => n + s.hits);
}

// MARK: Séance

/// Étapes d'une séance.
enum CoachStepKind { doubles, checkouts, pressure }

class CoachStep {
  const CoachStep(this.kind, {this.target, this.count = 0, this.prefer = const []});

  final CoachStepKind kind;

  /// Double visé (doubles, pression).
  final DartThrow? target;

  /// Volées (doubles), sorties (check-outs) ou manches (pression).
  final int count;

  /// Doubles faibles sur lesquels les sorties doivent finir.
  final List<DartThrow> prefer;

  String get title => switch (kind) {
    CoachStepKind.doubles => 'Doubles · ${target!.label}',
    CoachStepKind.checkouts => 'Sorties',
    CoachStepKind.pressure => 'Pression · ${target!.label}',
  };

  Map<String, Object?> toJson() => {'k': kind.name, 't': target?.label, 'n': count};
}

/// Séance du jour générée depuis le profil : les 2 doubles les plus faibles, des sorties qui
/// finissent dessus, puis un double acquis sous pression.
List<CoachStep> coachPlan(CoachProfile p) {
  final weak = p.weakest.take(2).map((s) => s.target).toList();
  final strong = p.acquired.target;
  return [
    for (final d in weak) CoachStep(CoachStepKind.doubles, target: d, count: 4),
    CoachStep(CoachStepKind.checkouts, count: 6, prefer: weak),
    CoachStep(CoachStepKind.pressure, target: strong, count: 3),
  ];
}

/// Une fléchette de la séance.
class CoachShot {
  const CoachShot({
    required this.step,
    required this.aim,
    required this.dart,
    this.x,
    this.y,
    required this.zone,
    required this.ok,
  });
  final int step;
  final DartThrow aim;
  final DartThrow dart;
  final double? x, y;

  /// Part du double éclairée (1 hors étape doubles).
  final double zone;

  /// Dans la zone (étape doubles), ou dans le double visé (sorties, pression).
  final bool ok;

  Map<String, Object?> toJson() => {
    'st': step,
    'a': aim.label,
    'd': dart.label,
    if (x != null) 'x': double.parse(x!.toStringAsFixed(1)),
    if (y != null) 'y': double.parse(y!.toStringAsFixed(1)),
    'z': double.parse(zone.toStringAsFixed(2)),
    'ok': ok,
  };
}

/// Un check-out joué (sorties ou pression).
class CoachCheckout {
  CoachCheckout(this.step, this.score, {this.ghost});
  final int step;
  final int score;

  /// Pression : volées avant que le fantôme finisse.
  final int? ghost;
  bool? ok;
  int darts = 0;

  Map<String, Object?> toJson() => {'st': step, 's': score, 'ok': ok ?? false, 'n': darts, 'g': ?ghost};
}

/// Séance du coach. Un seul joueur, tours de 3 fléchettes. Les positions des fléchettes
/// passent par [throwAt] ; corriger rejoue la séance avec les mêmes positions.
class CoachSession extends TurnGame {
  CoachSession(String name, {required this.plan, required CoachLevels levels, this.seed = 0})
    : _startLevels = levels.copy(),
      assert(plan.isNotEmpty),
      super([name]) {
    resetState();
  }

  final List<CoachStep> plan;
  final CoachLevels _startLevels;
  final int seed;

  /// Positions de toutes les fléchettes, dans l'ordre (null si inconnue).
  final List<(double, double)?> _positions = [];
  int _k = 0;

  late CoachLevels levels;
  late math.Random _rng;
  late int stepIndex;
  late int volleysInStep;
  final List<CoachShot> shots = [];
  final List<CoachCheckout> checkouts = [];

  /// Zone en cours (étape doubles), figée pour la volée : la lumière ne bouge pas pendant la volée.
  late double zone;

  // Check-out en cours (sorties, pression).
  CoachCheckout? current;
  late int remaining;
  late int dartsUsed;
  late int _volleyStart;

  CoachStep get step => plan[math.min(stepIndex, plan.length - 1)];
  bool get _isCheckout => step.kind != CoachStepKind.doubles;

  /// Fléchettes max pour le check-out en cours.
  int get maxDarts => switch (step.kind) {
    CoachStepKind.pressure => ghostVolleys * 3,
    _ => remainingRange.$2 <= 60 ? 6 : 9,
  };

  /// Pression : volées avant que le fantôme finisse.
  int get ghostVolleys => (3 - levels.pressure.floor()).clamp(1, 3);

  /// Plage de sortie du niveau actuel.
  (int, int) get remainingRange => checkoutRanges[levels.checkout.floor().clamp(0, checkoutRanges.length - 1)];

  /// Ce qui est visé par la prochaine fléchette.
  DartThrow? get aim {
    if (isFinished) return null;
    if (!_isCheckout) return step.target;
    final route = hint;
    return route?.first;
  }

  /// Route conseillée pour le check-out en cours.
  List<DartThrow>? get hint {
    if (!_isCheckout || isFinished || current == null) return null;
    return suggestCheckout(remaining, dartsLeft: math.min(3 - currentTurn.length, maxDarts - dartsUsed));
  }

  /// Volée dans le check-out en cours (1 à 3).
  int get volley => dartsUsed ~/ 3 + 1;

  /// Pression : reste du fantôme maintenant. Il part entre 40 et 120 et finit à sa dernière volée.
  int get ghostRest {
    final c = current;
    if (c == null || c.ghost == null) return 0;
    final g = c.ghost!, start = 40 + (c.score * 37) % 81, v = math.min(dartsUsed ~/ 3, g);
    return (start * (g - v) / g).round();
  }

  @override
  void resetState() {
    levels = _startLevels.copy();
    _rng = math.Random(seed);
    _k = 0;
    stepIndex = 0;
    volleysInStep = 0;
    shots.clear();
    checkouts.clear();
    current = null;
    dartsUsed = 0;
    remaining = 0;
    _volleyStart = 0;
    _enterStep();
  }

  void _enterStep() {
    volleysInStep = 0;
    current = null;
    if (step.kind == CoachStepKind.doubles) {
      zone = zoneFraction(levels.zone(step.target!));
    } else {
      zone = 1;
      _newCheckout();
    }
  }

  void _newCheckout() {
    final pressure = step.kind == CoachStepKind.pressure;
    final score = pressure ? _pressureScore() : _pickScore();
    current = CoachCheckout(stepIndex, score, ghost: pressure ? ghostVolleys : null);
    remaining = score;
    _volleyStart = score;
    dartsUsed = 0;
  }

  /// Score de sortie : dans la plage du niveau, de préférence fini sur un double faible,
  /// parfois une sortie souvent ratée.
  int _pickScore() {
    final (lo, hi) = remainingRange;
    final ok = [
      for (var n = lo; n <= hi; n++)
        if (suggestCheckout(n) != null) n,
    ];
    final prefer = step.prefer.map((d) => d.label).toSet();
    final good = ok.where((n) => prefer.contains(suggestCheckout(n)!.last.label)).toList();
    final pool = good.isNotEmpty && _rng.nextDouble() < 0.7 ? good : ok;
    return pool[_rng.nextInt(pool.length)];
  }

  /// Pression : une sortie qui finit sur le double acquis, dans la plage du niveau (ou en dessous).
  int _pressureScore() {
    final t = step.target!;
    for (var lvl = levels.checkout.floor().clamp(0, checkoutRanges.length - 1); lvl >= 0; lvl--) {
      final (lo, hi) = checkoutRanges[lvl];
      final ok = [
        for (var n = lo; n <= hi; n++)
          if (suggestCheckout(n)?.last == t) n,
      ];
      if (ok.isNotEmpty) return ok[_rng.nextInt(ok.length)];
    }
    return t.score;
  }

  /// Fléchette avec sa position (mm, centre (0, 0), y vers le bas).
  void throwAt(DartThrow d, double? x, double? y) {
    final i = _k;
    if (i < _positions.length) {
      _positions[i] = x == null || y == null ? null : (x, y);
    } else {
      _positions.add(x == null || y == null ? null : (x, y));
    }
    throwDart(d);
  }

  /// Corrige la fléchette [index] du tour en cours, avec sa position si connue.
  void correctAt(int index, DartThrow d, {double? x, double? y}) {
    final before = _k - currentTurn.length;
    final i = before + index;
    while (_positions.length <= i) {
      _positions.add(null);
    }
    _positions[i] = x == null || y == null ? null : (x, y);
    _positions.length = math.min(_positions.length, before + math.max(currentTurn.length, index + 1));
    correctDart(index, d);
  }

  /// Chrono de la pression fini : le reste de la volée compte comme raté.
  void timeUp() {
    while (!awaitingNextPlayer && !isFinished) {
      throwAt(const DartThrow.miss(), null, null);
    }
  }

  @override
  int scoreOf(int player) {
    if (shots.isEmpty) return 0;
    return (shots.where((s) => s.ok).length * 100 / shots.length).round();
  }

  @override
  void onDart(int player, DartThrow d) {
    final pos = _k < _positions.length ? _positions[_k] : null;
    _k++;
    final x = pos?.$1, y = pos?.$2;
    if (step.kind == CoachStepKind.doubles) {
      final t = step.target!;
      final ok = inZone(t, d, x, y, zone);
      shots.add(CoachShot(step: stepIndex, aim: t, dart: d, x: x, y: y, zone: zone, ok: ok));
      levels.zones[t.label] = coachStep(levels.zone(t), ok);
      return;
    }
    final c = current!;
    final onDouble = (remaining <= 40 && remaining.isEven) || remaining == 50;
    if (onDouble) {
      final t = remaining == 50 ? DartThrow.bull : DartThrow.double(remaining ~/ 2);
      shots.add(CoachShot(step: stepIndex, aim: t, dart: d, x: x, y: y, zone: 1, ok: d == t));
    }
    dartsUsed++;
    final left = remaining - d.score;
    if (left == 0 && d.isDouble) {
      remaining = 0;
      _endCheckout(c, true);
      endTurn();
    } else if (left < 0 || left == 1 || left == 0) {
      remaining = _volleyStart;
      dartsUsed = ((dartsUsed + 2) ~/ 3) * 3;
      if (dartsUsed >= maxDarts) _endCheckout(c, false);
      endTurn();
    } else {
      remaining = left;
      if (dartsUsed >= maxDarts) _endCheckout(c, false);
    }
  }

  void _endCheckout(CoachCheckout c, bool ok) {
    c
      ..ok = ok
      ..darts = dartsUsed;
    checkouts.add(c);
    if (step.kind == CoachStepKind.pressure) {
      levels.pressure = coachStep(levels.pressure, ok, max: 2.99);
    } else {
      levels.checkout = coachStep(levels.checkout, ok, max: checkoutRanges.length - 0.01);
    }
  }

  @override
  void onTurnEnd(int player, List<DartThrow> turn) {
    if (step.kind == CoachStepKind.doubles) {
      volleysInStep++;
      if (volleysInStep >= step.count) _nextStep();
      return;
    }
    _volleyStart = remaining;
    if (current?.ok != null) {
      volleysInStep++;
      if (volleysInStep >= step.count) {
        _nextStep();
      } else {
        _newCheckout();
      }
    }
  }

  /// Volée suivante (fléchettes retirées) : la zone suit le niveau du double.
  @override
  void onRoundEnd() {
    if (step.kind == CoachStepKind.doubles && volleysInStep > 0) zone = zoneFraction(levels.zone(step.target!));
  }

  void _nextStep() {
    stepIndex++;
    if (stepIndex >= plan.length) {
      stepIndex = plan.length - 1;
      finish(0);
      return;
    }
    _enterStep();
  }

  /// Réussite d'une étape : touches dans la zone (doubles) ou sorties réussies.
  ({int ok, int total}) resultOf(int step) {
    final s = plan[step];
    if (s.kind == CoachStepKind.doubles) {
      final list = shots.where((x) => x.step == step);
      return (ok: list.where((x) => x.ok).length, total: list.length);
    }
    final list = checkouts.where((c) => c.step == step);
    return (ok: list.where((c) => c.ok == true).length, total: list.length);
  }

  /// Fléchettes dans le double visé, toute la séance.
  ({int ok, int total}) get doubleHits {
    final hit = shots.where((s) => s.dart == s.aim).length;
    return (ok: hit, total: shots.length);
  }
}
