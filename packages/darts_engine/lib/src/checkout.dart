import 'dart_throw.dart';

final List<DartThrow> _all = [
  for (var s = 20; s >= 1; s--) ...[DartThrow.triple(s), DartThrow.double(s), DartThrow.single(s)],
  DartThrow.bull,
  DartThrow.outerBull,
];

final List<DartThrow> _doubles = [for (var s = 20; s >= 1; s--) DartThrow.double(s), DartThrow.bull];

/// Doubles préférés pour finir, du meilleur au moins bon.
const _preferredDoubles = [20, 16, 18, 12, 10, 8, 14, 6, 4, 2, 19, 17, 15, 13, 11, 9, 7, 5, 3, 1, 25];

int _doubleRank(DartThrow d) => _preferredDoubles.indexOf(d.sector);

/// Suggestion de sortie pour [remaining] avec [dartsLeft] fléchettes (1 à 3),
/// en double out. Renvoie null si aucune sortie n'est possible.
///
/// Préfère le moins de fléchettes, puis un double "propre" (D20, D16...),
/// puis les gros segments en premier.
List<DartThrow>? suggestCheckout(int remaining, {int dartsLeft = 3}) {
  if (remaining < 2 || remaining > 170 || dartsLeft < 1) return null;

  List<DartThrow>? best;
  int bestRank = 1 << 30;

  void consider(List<DartThrow> path) {
    // Rang : nombre de fléchettes d'abord, puis qualité du double final,
    // puis on évite les simples inutiles.
    final singles = path.where((d) => d.multiplier == 1).length;
    final rank = path.length * 10000 + _doubleRank(path.last) * 10 + singles;
    if (rank < bestRank) {
      bestRank = rank;
      best = path;
    }
  }

  for (final d in _doubles) {
    if (d.score == remaining) consider([d]);
  }
  if (dartsLeft >= 2) {
    for (final a in _all) {
      for (final d in _doubles) {
        if (a.score + d.score == remaining) consider([a, d]);
      }
    }
  }
  if (dartsLeft >= 3 && best == null) {
    for (final a in _all) {
      for (final b in _all) {
        for (final d in _doubles) {
          if (a.score + b.score + d.score == remaining) consider([a, b, d]);
        }
      }
    }
  }
  return best;
}
