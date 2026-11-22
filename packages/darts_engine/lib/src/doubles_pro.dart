import 'dart:math' as math;

import 'coach.dart';
import 'dart_throw.dart';
import 'modes.dart';

// Doubles Pro : une routine fixe, chiffrée, sur tous les doubles.
//
// 1. Diagnostic : 15 fléchettes sur D16, 15 sur D20. Écart moyen en mm (routine de Bunting).
// 2. Chaînes : D16, D8, D4, D2, D1. Le simple du numéro visé fait descendre (on apprend où rater).
// 3. Aléatoire : 30 fléchettes, un double différent à chaque fois, pondéré par la fréquence en match.
// 4. Échelle : 32, 40, 56, 80, 100, 121 en 9 fléchettes. Raté, retour à 32.

/// Blocs d'une séance, dans l'ordre.
enum DpBlock { diagnostic, chains, random, ladder }

extension DpBlockText on DpBlock {
  String get title => switch (this) {
    DpBlock.diagnostic => 'Diagnostic',
    DpBlock.chains => 'Chaînes',
    DpBlock.random => 'Aléatoire',
    DpBlock.ladder => 'Échelle de pression',
  };

  String get desc => switch (this) {
    DpBlock.diagnostic => '15 sur D16, 15 sur D20. Ta tendance en mm.',
    DpBlock.chains => 'D16, D8, D4, D2. Le simple te fait descendre.',
    DpBlock.random => '30 fléchettes, un double différent à chaque fois.',
    DpBlock.ladder => '32 à 121 en 9 fléchettes. Raté, retour à 32.',
  };
}

/// Fléchettes par double au diagnostic.
const dpDiagnosticDarts = 15;

/// Doubles du diagnostic.
const dpDiagnosticTargets = [DartThrow.double(16), DartThrow.double(20)];

/// Départs des chaînes : D16 (jusqu'à D1), D20 (D10, D5), D12 (D6, D3), D18 (D9), D16.
const dpChainStarts = [32, 40, 24, 36, 32];

/// Fléchettes max par chaîne.
const dpChainMaxDarts = 9;

/// Fléchettes du bloc aléatoire.
const dpRandomDarts = 30;

/// Marches de l'échelle.
const dpLadder = [32, 40, 56, 80, 100, 121];

/// Fléchettes par marche.
const dpLadderDarts = 9;

/// Essais sur l'échelle.
const dpLadderTries = 6;

/// Repères de réussite sur les doubles (%), d'après les stats PDC et les conseils des pros.
const dpBenchmarks = [('Club, bon niveau', 30), ('Humphries', 42), ('Van Gerwen', 45), ('Bunting, bon standard', 50)];

/// Fréquence des doubles en fin de manche.
double dpWeight(DartThrow d) => switch (d.sector) {
  20 || 16 || 18 || 12 || 10 || 8 => 1.0,
  14 || 6 || 4 || 2 || 25 => 0.8,
  _ => 0.55,
};

/// Où une fléchette tombe par rapport au double visé.
enum DpMiss { hit, outside, inside, side }

/// Classe une fléchette visée sur [aim] : dans le double, dehors, dedans (simple), à côté.
DpMiss dpMissOf(DartThrow aim, DartThrow d, double? x, double? y) {
  if (d == aim) return DpMiss.hit;
  if (x != null && y != null && aim.sector != 25) {
    final e = aimError(aim, x, y);
    if (e.tangential.abs() <= doubleMidRadius * 9 * math.pi / 180) {
      return e.radial > 0 ? DpMiss.outside : DpMiss.inside;
    }
    return DpMiss.side;
  }
  if (d.isMiss) return DpMiss.outside;
  if (d.sector == aim.sector) return DpMiss.inside;
  return DpMiss.side;
}

/// Une fléchette de la séance.
class DpShot {
  const DpShot({required this.block, required this.aim, required this.dart, this.x, this.y});
  final DpBlock block;
  final DartThrow aim;
  final DartThrow dart;
  final double? x, y;

  bool get ok => dart == aim;
  DpMiss get miss => dpMissOf(aim, dart, x, y);

  Map<String, Object?> toJson() => {
    'b': block.name,
    'a': aim.label,
    'd': dart.label,
    if (x != null) 'x': double.parse(x!.toStringAsFixed(1)),
    if (y != null) 'y': double.parse(y!.toStringAsFixed(1)),
    'ok': ok,
  };
}

/// Une chaîne ou une marche de l'échelle.
class DpRun {
  DpRun(this.block, this.start);
  final DpBlock block;
  final int start;
  bool? ok;
  int darts = 0;

  /// Chaîne : double sur lequel elle a fini (réussie ou non).
  DartThrow? last;

  Map<String, Object?> toJson() => {'b': block.name, 's': start, 'ok': ok ?? false, 'n': darts, 'l': ?last?.label};
}

/// Écart moyen d'une série sur un double : radial (+ dehors), tangentiel (+ sens horaire),
/// dispersion autour du point moyen (mm).
class DpBias {
  const DpBias({this.radial = 0, this.tangential = 0, this.spread = 0, this.placed = 0});
  final double radial, tangential, spread;
  final int placed;

  factory DpBias.of(Iterable<DpShot> shots) {
    final e = [
      for (final s in shots)
        if (s.x != null && s.y != null) aimError(s.aim, s.x!, s.y!),
    ];
    if (e.isEmpty) return const DpBias();
    final r = e.fold<double>(0, (a, b) => a + b.radial) / e.length;
    final t = e.fold<double>(0, (a, b) => a + b.tangential) / e.length;
    final v = e.fold<double>(0, (a, b) => a + math.pow(b.radial - r, 2) + math.pow(b.tangential - t, 2)) / e.length;
    return DpBias(radial: r, tangential: t, spread: math.sqrt(v), placed: e.length);
  }
}

/// Séance Doubles Pro. Un seul joueur, volées de 3. Positions par [throwAt] ;
/// corriger rejoue la séance avec les mêmes positions.
class DoublesProSession extends TurnGame {
  DoublesProSession(String name, {this.blocks = DpBlock.values, this.seed = 0})
    : assert(blocks.isNotEmpty),
      super([name]) {
    resetState();
  }

  final List<DpBlock> blocks;
  final int seed;

  final List<(double, double)?> _positions = [];
  int _k = 0;

  late math.Random _rng;
  late int blockIndex;

  /// Fléchettes tirées dans le bloc (diagnostic, aléatoire).
  late int dartsInBlock;
  final List<DpShot> shots = [];
  final List<DpRun> runs = [];

  /// Doubles tirés au sort pour le bloc aléatoire.
  final List<DartThrow> randomTargets = [];

  // Chaîne ou marche en cours.
  DpRun? current;
  late int remaining;
  late int _volleyStart;

  /// Échelle : marche en cours (index dans [dpLadder]) et meilleure marche réussie.
  late int rung;
  int? bestRung;

  DpBlock get block => blocks[math.min(blockIndex, blocks.length - 1)];

  /// Ce qui est visé par la prochaine fléchette.
  DartThrow? get aim {
    if (isFinished) return null;
    switch (block) {
      case DpBlock.diagnostic:
        return dpDiagnosticTargets[math.min(dartsInBlock ~/ dpDiagnosticDarts, 1)];
      case DpBlock.random:
        return randomTargets[math.min(dartsInBlock, randomTargets.length - 1)];
      case DpBlock.chains:
        return _doubleFor(remaining);
      case DpBlock.ladder:
        return _doubleFor(remaining);
    }
  }

  static DartThrow? _doubleFor(int rest) => rest == 50
      ? DartThrow.bull
      : rest >= 2 && rest <= 40 && rest.isEven
      ? DartThrow.double(rest ~/ 2)
      : null;

  /// Index de la chaîne ou de l'essai d'échelle en cours (0...).
  int get runIndex => runs.where((r) => r.block == block).length;

  /// Fléchettes jouées dans la chaîne ou la marche en cours.
  int get runDarts => current?.darts ?? 0;

  @override
  void resetState() {
    _rng = math.Random(seed);
    _k = 0;
    blockIndex = 0;
    shots.clear();
    runs.clear();
    randomTargets.clear();
    current = null;
    remaining = 0;
    _volleyStart = 0;
    rung = 0;
    bestRung = null;
    _enterBlock();
  }

  void _enterBlock() {
    dartsInBlock = 0;
    current = null;
    switch (block) {
      case DpBlock.diagnostic:
        break;
      case DpBlock.random:
        _drawTargets();
      case DpBlock.chains:
        _newRun(dpChainStarts[0]);
      case DpBlock.ladder:
        rung = 0;
        _newRun(dpLadder[0]);
    }
  }

  /// 30 doubles au hasard, pondérés par la fréquence en match, jamais deux fois le même à la suite.
  void _drawTargets() {
    randomTargets.clear();
    final total = coachDoubles.fold<double>(0, (a, d) => a + dpWeight(d));
    while (randomTargets.length < dpRandomDarts) {
      var r = _rng.nextDouble() * total;
      var pick = coachDoubles.last;
      for (final d in coachDoubles) {
        r -= dpWeight(d);
        if (r <= 0) {
          pick = d;
          break;
        }
      }
      if (randomTargets.isNotEmpty && randomTargets.last == pick) continue;
      randomTargets.add(pick);
    }
  }

  void _newRun(int start) {
    current = DpRun(block, start);
    remaining = start;
    _volleyStart = start;
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

  /// Retire la fléchette [index] du tour en cours, avec sa position (coup fantôme, annulation).
  void removeAt(int index) {
    if (index < 0 || index >= currentTurn.length) return;
    final i = _k - currentTurn.length + index;
    if (i < _positions.length) _positions.removeAt(i);
    _positions.length = math.min(_positions.length, _k - 1);
    removeDart(index);
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

  /// Réussite sur les doubles de toute la séance (%).
  @override
  int scoreOf(int player) => shots.isEmpty ? 0 : (shots.where((s) => s.ok).length * 100 / shots.length).round();

  @override
  void onDart(int player, DartThrow d) {
    final pos = _k < _positions.length ? _positions[_k] : null;
    _k++;
    final x = pos?.$1, y = pos?.$2;
    final a = aim;
    switch (block) {
      case DpBlock.diagnostic:
      case DpBlock.random:
        shots.add(DpShot(block: block, aim: a!, dart: d, x: x, y: y));
        dartsInBlock++;
      case DpBlock.chains:
        _chainDart(d, a!, x, y);
      case DpBlock.ladder:
        _ladderDart(d, a, x, y);
    }
  }

  void _chainDart(DartThrow d, DartThrow a, double? x, double? y) {
    final c = current!;
    shots.add(DpShot(block: block, aim: a, dart: d, x: x, y: y));
    c.darts++;
    if (d == a) {
      _endRun(c, true, a);
      endTurn();
      return;
    }
    if (d.sector == a.sector && d.multiplier == 1 && a.sector != 25) {
      // Le simple fait descendre : D16 raté dedans laisse 16, donc D8.
      remaining -= d.score;
      if (_doubleFor(remaining) == null) {
        _endRun(c, false, a);
        endTurn();
        return;
      }
    }
    if (c.darts >= dpChainMaxDarts) {
      _endRun(c, false, a);
      endTurn();
    }
  }

  void _ladderDart(DartThrow d, DartThrow? a, double? x, double? y) {
    final c = current!;
    if (a != null) shots.add(DpShot(block: block, aim: a, dart: d, x: x, y: y));
    c.darts++;
    final left = remaining - d.score;
    if (left == 0 && d.isDouble) {
      remaining = 0;
      _endRun(c, true, d);
      endTurn();
    } else if (left < 0 || left == 1 || left == 0) {
      // Bust : retour au score du début de la volée, la volée est perdue.
      remaining = _volleyStart;
      c.darts = ((c.darts + 2) ~/ 3) * 3;
      if (c.darts >= dpLadderDarts) _endRun(c, false, null);
      endTurn();
    } else {
      remaining = left;
      if (c.darts >= dpLadderDarts) _endRun(c, false, null);
    }
  }

  void _endRun(DpRun c, bool ok, DartThrow? last) {
    c
      ..ok = ok
      ..last = last;
    runs.add(c);
    if (c.block == DpBlock.ladder) {
      if (ok) {
        bestRung = math.max(bestRung ?? -1, rung);
        rung = math.min(rung + 1, dpLadder.length - 1);
      } else {
        rung = 0;
      }
    }
  }

  @override
  void onTurnEnd(int player, List<DartThrow> turn) {
    switch (block) {
      case DpBlock.diagnostic:
        if (dartsInBlock >= dpDiagnosticDarts * dpDiagnosticTargets.length) _nextBlock();
      case DpBlock.random:
        if (dartsInBlock >= dpRandomDarts) _nextBlock();
      case DpBlock.chains:
        _volleyStart = remaining;
        if (current?.ok != null) {
          final n = runIndex;
          if (n >= dpChainStarts.length) {
            _nextBlock();
          } else {
            _newRun(dpChainStarts[n]);
          }
        }
      case DpBlock.ladder:
        _volleyStart = remaining;
        if (current?.ok != null) {
          if (runIndex >= dpLadderTries) {
            _nextBlock();
          } else {
            _newRun(dpLadder[rung]);
          }
        }
    }
  }

  void _nextBlock() {
    blockIndex++;
    if (blockIndex >= blocks.length) {
      blockIndex = blocks.length - 1;
      current = null;
      finish(0);
      return;
    }
    _enterBlock();
  }

  /// Fléchettes du bloc [b].
  Iterable<DpShot> shotsOf(DpBlock b) => shots.where((s) => s.block == b);

  /// Réussite sur les doubles d'un bloc.
  ({int ok, int total}) hitsOf(DpBlock b) {
    final l = shotsOf(b);
    return (ok: l.where((s) => s.ok).length, total: l.length);
  }

  /// Chaînes ou marches réussies d'un bloc.
  ({int ok, int total}) runsOf(DpBlock b) {
    final l = runs.where((r) => r.block == b);
    return (ok: l.where((r) => r.ok == true).length, total: l.length);
  }

  /// Fléchettes moyennes par chaîne réussie, null sans réussite.
  double? get chainAverage {
    final ok = runs.where((r) => r.block == DpBlock.chains && r.ok == true).toList();
    if (ok.isEmpty) return null;
    return ok.fold<int>(0, (n, r) => n + r.darts) / ok.length;
  }

  /// Plus haute marche réussie (score), null sans réussite.
  int? get bestLadder => bestRung == null ? null : dpLadder[bestRung!];

  /// Diagnostic d'un double : touchés, dehors, dedans, à côté, écart moyen.
  ({int hit, int outside, int inside, int side, DpBias bias}) diagnosticOf(DartThrow target) {
    final l = shotsOf(DpBlock.diagnostic).where((s) => s.aim == target).toList();
    int n(DpMiss m) => l.where((s) => s.miss == m).length;
    return (
      hit: n(DpMiss.hit),
      outside: n(DpMiss.outside),
      inside: n(DpMiss.inside),
      side: n(DpMiss.side),
      bias: DpBias.of(l),
    );
  }
}
