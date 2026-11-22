import 'package:darts_engine/darts_engine.dart';

import '../history/history_store.dart';
import '../stats/owner_stats.dart';

/// Ce que le coach sait d'un joueur, lu dans l'historique :
/// séances du coach et de Doubles Pro (positions exactes), séries sur un double (positions), X01 en double out (cases).
class CoachStore {
  CoachStore._(this.stats);

  /// Profil du joueur [id] ("owner", identifiant d'iPhone ou de profil).
  factory CoachStore.of(String id, {List<Map<String, Object?>>? history}) =>
      CoachStore._(OwnerStats(history ?? HistoryStore.instance.all(), id: id));

  factory CoachStore.forName(String name) => CoachStore.of(HistoryStore.playerId(name));

  final OwnerStats stats;

  Iterable<StatEntry> get sessions => stats.entries.where((e) => e.kind == GameMode.coach.name);

  late final CoachProfile profile = _build();

  CoachProfile _build() {
    final tries = <DoubleTry>[];
    final checkouts = <CheckoutTry>[];
    CoachLevels? levels;
    for (final e in stats.entries) {
      if (e.kind == GameMode.coach.name) {
        for (final s in (e.p['shots'] as List? ?? const [])) {
          if (s is! Map) continue;
          final aim = parseDart('${s['a']}'), d = parseDart('${s['d']}');
          if (!aim.isDouble) continue;
          tries.add(DoubleTry(aim, d == aim, x: (s['x'] as num?)?.toDouble(), y: (s['y'] as num?)?.toDouble()));
        }
        for (final c in (e.p['checkouts'] as List? ?? const [])) {
          if (c is Map && c['s'] is num) checkouts.add(CheckoutTry((c['s'] as num).toInt(), c['ok'] == true));
        }
        final l = e.p['levels'];
        if (l is Map) levels = CoachLevels.fromJson(l.cast<String, Object?>());
      } else if (e.kind == GameMode.doublesPro.name) {
        // Doubles Pro : chaque fléchette sur un double, avec sa position.
        for (final s in (e.p['shots'] as List? ?? const [])) {
          if (s is! Map) continue;
          final aim = parseDart('${s['a']}'), d = parseDart('${s['d']}');
          if (!aim.isDouble) continue;
          tries.add(DoubleTry(aim, d == aim, x: (s['x'] as num?)?.toDouble(), y: (s['y'] as num?)?.toDouble()));
        }
      } else if (e.target && e.targetKey != null && e.targetKey!.startsWith('D')) {
        final aim = parseDart(e.targetKey!);
        if (!aim.isDouble) continue;
        for (final t in e.throws) {
          tries.add(DoubleTry(aim, t.dart == aim, x: t.x, y: t.y));
        }
      } else if (e.x01 && e.doubleOut) {
        _x01(e, tries, checkouts);
      }
    }
    return CoachProfile(tries: tries, checkouts: checkouts, levels: levels);
  }

  /// X01 : chaque fléchette tirée sur un reste finissable en une fléchette est un essai sur ce double,
  /// chaque tour commencé sur une sortie possible est un check-out tenté.
  static void _x01(StatEntry e, List<DoubleTry> tries, List<CheckoutTry> checkouts) {
    for (final leg in e.legs) {
      var rem = e.startScore;
      for (final r in leg) {
        if (suggestCheckout(rem) != null) checkouts.add(CheckoutTry(rem, r.checkout));
        var x = rem;
        for (final l in r.darts) {
          final d = parseDart(l);
          final aim = x == 50 ? DartThrow.bull : (x > 0 && x <= 40 && x.isEven ? DartThrow.double(x ~/ 2) : null);
          if (aim != null) tries.add(DoubleTry(aim, d == aim));
          x -= d.score;
          if (x <= 1) break;
        }
        rem = r.rest;
      }
    }
  }

  /// Séances déjà faites aujourd'hui.
  int get todayCount {
    final now = DateTime.now();
    return sessions.where((e) => e.at.year == now.year && e.at.month == now.month && e.at.day == now.day).length;
  }

  /// Graine de la séance : la même toute la journée, une autre pour chaque séance en plus.
  int seedFor(String id) {
    final now = DateTime.now();
    return Object.hash(id, now.year, now.month, now.day, todayCount) & 0x7fffffff;
  }

  /// Pour l'iPhone et le web : carte des doubles, niveaux, une ligne par séance.
  Map<String, Object?> toJson() {
    final p = profile;
    return {
      'doubles': [
        for (final s in p.skills.values)
          {
            'label': s.label,
            'attempts': s.attempts,
            'hits': s.hits,
            'pct': s.pct,
            if (s.placed > 0) 'radial': double.parse(s.radial.toStringAsFixed(1)),
            if (s.placed > 0) 'tangential': double.parse(s.tangential.toStringAsFixed(1)),
            'zone': (zoneFraction(p.levels.zone(s.target)) * 100).round(),
          },
      ],
      'weakest': [for (final s in p.weakest.take(2)) s.label],
      'acquired': p.acquired.label,
      'levels': p.levels.toJson(),
      'checkoutRange': () {
        final (lo, hi) = checkoutRanges[p.levels.checkout.floor().clamp(0, checkoutRanges.length - 1)];
        return '$lo-$hi';
      }(),
      'sessions': [
        for (final e in sessions)
          {
            'at': e.at.toIso8601String(),
            'zonePct': e.p['zonePct'],
            'doublePct': e.p['doublePct'],
            'checkouts': e.p['checkoutOk'],
            'checkoutTotal': e.p['checkoutTotal'],
            'pressure': e.p['pressureOk'],
            'pressureTotal': e.p['pressureTotal'],
          },
      ],
    };
  }
}
