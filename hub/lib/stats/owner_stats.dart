import 'dart:math' as math;

import 'package:darts_engine/darts_engine.dart';

// Statistiques du propriétaire, calculées depuis l'historique (history.jsonl).
// Tout est pur Dart pour rester testable sans écran.

int _int(Object? v) => v is num ? v.toInt() : 0;

const monthsFr = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];
const monthsShortFr = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
const daysShortFr = ['Lun.', 'Mar.', 'Mer.', 'Jeu.', 'Ven.', 'Sam.', 'Dim.'];

/// "62,4"
String fr1(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

/// "+4,8" ou "-1,2"
String signed1(double v) => '${v >= 0 ? '+' : '-'}${fr1(v.abs())}';

/// "3 280"
String thousands(int n) {
  final s = n.abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return b.toString();
}

/// "le 2 nov."
String dayFr(DateTime d) => 'le ${d.day} ${monthsShortFr[d.month - 1]}';

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Libellé d'une fléchette (T20, D16, S5, BULL, 25, MISS) vers la fléchette.
DartThrow parseDart(String l) {
  if (l == 'BULL') return DartThrow.bull;
  if (l == '25') return DartThrow.outerBull;
  if (l.length < 2) return const DartThrow.miss();
  final m = 'SDT'.indexOf(l[0]) + 1;
  final s = int.tryParse(l.substring(1)) ?? 0;
  if (m < 1 || s < 1 || s > 20) return const DartThrow.miss();
  return DartThrow(s, m);
}

/// Un tour de X01 enregistré.
class TurnRow {
  TurnRow(this.leg, this.darts, this.total, this.rest, this.bust);
  final int leg;
  final List<String> darts;
  final int total;
  final int rest;
  final bool bust;
  bool get checkout => rest == 0 && !bust;
}

/// Une partie (ou un entraînement) de l'historique, vue du propriétaire.
class StatEntry {
  StatEntry(this.m, this.p, this.at);
  final Map<String, Object?> m;
  final Map<String, Object?> p;
  final DateTime at;

  String get kind => m['kind'] as String? ?? '';
  String get mode => m['mode'] as String? ?? kind;
  bool get drill => kind == 'training';
  bool get practice => drill || m['training'] == true;
  bool get x01 => kind == 'x01';
  bool get volleys => drill && m['drill'] == 'volleys';
  bool get target => drill && m['drill'] == 'target';
  String? get targetKey => m['target'] as String?;
  int get length => _int(m['length']);
  int get darts => _int(p['darts']);
  int get score => _int(p['score']);
  int get best => _int(p['best']);
  bool get won => p['won'] == true;
  int get startScore => int.tryParse(mode) ?? 501;
  bool get doubleOut => m['doubleOut'] != false;

  List<Map<String, Object?>> get players => [
    for (final o in (m['players'] as List? ?? const [])) (o as Map).cast<String, Object?>(),
  ];

  /// Une vraie partie à plusieurs (pas un entraînement).
  bool get versus => !practice && players.length >= 2;

  /// Points marqués et fléchettes qui comptent pour la moyenne (X01 et volées libres).
  int get points => x01 ? _int(p['scored']) : (volleys ? score : 0);
  int get pointDarts => x01 || volleys ? darts : 0;

  late final List<TurnRow> rows = [
    if (x01)
      for (final r in (p['turns'] as List? ?? const []))
        TurnRow(
          _int((r as Map)['leg']),
          [for (final d in (r['darts'] as List? ?? const [])) '$d'],
          _int(r['total']),
          _int(r['rest']),
          r['bust'] == true,
        ),
  ];

  /// Score de chaque tour (X01, bust compté 0) ou de chaque volée libre.
  List<int> get turnScores => x01
      ? [for (final r in rows) r.bust ? 0 : r.total]
      : (volleys ? [for (final s in (p['scores'] as List? ?? const [])) _int(s)] : const []);

  /// Fléchettes avec position, enregistrées pendant les séries.
  List<({DartThrow dart, double x, double y})> get throws => [
    for (final t in (p['throws'] as List? ?? const []))
      if (t is Map)
        (
          dart: parseDart('${t['d']}'),
          x: (t['x'] as num?)?.toDouble() ?? 0,
          y: (t['y'] as num?)?.toDouble() ?? 0,
        ),
  ];

  /// Tours regroupés par manche.
  List<List<TurnRow>> get legs {
    final out = <int, List<TurnRow>>{};
    for (final r in rows) {
      out.putIfAbsent(r.leg, () => []).add(r);
    }
    return out.values.toList();
  }
}

/// Moyenne 3 fléchettes d'un lot de parties, null sans fléchette.
double? average(Iterable<StatEntry> es) {
  var pts = 0, d = 0;
  for (final e in es) {
    pts += e.points;
    d += e.pointDarts;
  }
  return d == 0 ? null : pts / d * 3;
}

class RecordLine {
  const RecordLine(this.icon, this.label, this.when, this.value);
  final String icon;
  final String label;
  final String when;
  final String value;
}

class DoubleRate {
  const DoubleRate(this.label, this.tries, this.hits);
  final String label;
  final int tries;
  final int hits;
  int get pct => tries == 0 ? 0 : (hits * 100 / tries).round();
}

class SeriesCard {
  const SeriesCard(this.label, this.best, this.last, this.fresh);
  final String label;
  final int? best;
  final List<int> last;
  final bool fresh;
}

class Rival {
  Rival(this.name);
  String name;
  int wins = 0, losses = 0;
  DateTime? lastAt;
  String lastMode = '';
  final Map<String, (int, int)> byMode = {};
  int get games => wins + losses;
}

class SectorShare {
  const SectorShare(this.label, this.pct);
  final String label;
  final int pct;
}

class Tile {
  const Tile(this.icon, this.label, this.value, this.sub);
  final String icon;
  final String label;
  final String value;
  final String sub;
}

/// Toutes les stats d'un joueur (le propriétaire par défaut).
class OwnerStats {
  OwnerStats(List<Map<String, Object?>> all, {this.id = 'owner', DateTime? now}) : now = now ?? DateTime.now() {
    for (final m in all) {
      final ps = m['players'];
      if (ps is! List) continue;
      final p = ps.whereType<Map>().where((p) => p['id'] == id).firstOrNull;
      if (p == null) continue;
      final at = DateTime.tryParse(m['at'] as String? ?? '');
      if (at == null) continue;
      entries.add(StatEntry(m, p.cast<String, Object?>(), at));
    }
    entries.sort((a, b) => a.at.compareTo(b.at));
  }

  final String id;
  final DateTime now;

  /// Plus ancienne d'abord.
  final List<StatEntry> entries = [];

  bool get isEmpty => entries.isEmpty;

  Iterable<StatEntry> since(Duration d) => entries.where((e) => e.at.isAfter(now.subtract(d)));
  Iterable<StatEntry> between(DateTime a, DateTime b) => entries.where((e) => !e.at.isBefore(a) && e.at.isBefore(b));

  // MARK: Résumé

  int get games => entries.where((e) => !e.drill).length;
  int get dartsTotal => entries.fold(0, (n, e) => n + e.darts);

  /// "142 parties, 3 280 fléchettes depuis août"
  String get subtitle {
    if (isEmpty) return 'Pas encore de partie enregistrée';
    final first = entries.first.at;
    final g = games;
    return '${thousands(g)} partie${g > 1 ? 's' : ''}, ${thousands(dartsTotal)} fléchettes depuis ${monthsFr[first.month - 1]}';
  }

  /// Moyenne des 30 derniers jours, sinon de tout l'historique.
  double? get averageNow => average(since(const Duration(days: 30))) ?? average(entries);

  /// Progression : 30 derniers jours contre il y a 3 mois, sinon contre les débuts.
  String? get averageTrend {
    final cur = averageNow;
    if (cur == null) return null;
    final old = average(between(now.subtract(const Duration(days: 120)), now.subtract(const Duration(days: 90))));
    if (old != null) return '${signed1(cur - old)} en 3 mois';
    final scoring = entries.where((e) => e.pointDarts > 0).toList();
    if (scoring.isEmpty) return null;
    final start = scoring.first.at;
    if (now.difference(start).inDays < 14) return null;
    final first = average(between(start, start.add(const Duration(days: 7))));
    if (first == null) return null;
    return '${signed1(cur - first)} depuis ${monthsShortFr[start.month - 1]}';
  }

  /// Sorties réussies sur double, en %.
  int? get checkoutPct {
    var t = 0, h = 0;
    for (final e in entries.where((e) => e.x01 && e.doubleOut)) {
      t += _int(e.p['tries']);
      h += _int(e.p['hits']);
    }
    return t == 0 ? null : (h * 100 / t).round();
  }

  int count180(Iterable<StatEntry> es) => es.fold(0, (n, e) => n + e.turnScores.where((s) => s == 180).length);

  int get total180 => count180(entries);
  int get month180 => count180(entries.where((e) => e.at.year == now.year && e.at.month == now.month));

  int? get winPct {
    final v = entries.where((e) => e.versus).toList();
    if (v.isEmpty) return null;
    return (v.where((e) => e.won).length * 100 / v.length).round();
  }

  static DateTime monday(DateTime d) => _day(d).subtract(Duration(days: d.weekday - 1));

  /// Moyenne de chaque semaine, les 12 dernières (null sans partie cette semaine-là).
  List<({DateTime start, double? avg})> get weekly {
    final m = monday(now);
    return [
      for (var i = 11; i >= 0; i--)
        () {
          final s = m.subtract(Duration(days: 7 * i));
          return (start: s, avg: average(between(s, s.add(const Duration(days: 7)))));
        }(),
    ];
  }

  String get weeklyCaption {
    final w = weekly.where((w) => w.avg != null).toList();
    if (w.isEmpty) return 'Joue au X01 ou en volées libres pour tracer ta courbe.';
    final best = w.map((w) => w.avg!).reduce(math.max);
    final last = w.last.avg!;
    if (w.length > 1 && last >= best) return "Meilleure semaine : ${fr1(best)}. Tu n'as jamais été aussi haut.";
    return 'Meilleure semaine : ${fr1(best)}. Cette semaine : ${fr1(last)}.';
  }

  List<RecordLine> get records {
    final out = <RecordLine>[];
    // Meilleur tour, au X01 ou en volées libres.
    (int, StatEntry)? bestTurn;
    for (final e in entries) {
      for (final s in e.turnScores) {
        if (bestTurn == null || s > bestTurn.$1) bestTurn = (s, e);
      }
    }
    if (bestTurn != null && bestTurn.$1 > 0) {
      final e = bestTurn.$2;
      out.add(RecordLine('flame', 'Meilleur tour', '${dayFr(e.at)}, ${e.x01 ? 'au ${e.mode}' : 'en volées libres'}', '${bestTurn.$1}'));
    }
    final out1 = bestCheckout;
    if (out1 != null) {
      out.add(RecordLine('log-out', 'Meilleure sortie', '${out1.darts.join(' ')}, ${dayFr(out1.at)}', '${out1.total}'));
    }
    final short = shortestLeg;
    if (short != null) {
      out.add(RecordLine('zap', 'Partie la plus courte', '${short.start} en ${short.darts} fléchettes', '${short.darts}'));
    }
    // Record de série : T20 d'abord, sinon la cible la plus jouée.
    final series = entries.where((e) => e.target).toList();
    if (series.isNotEmpty) {
      final keys = <String, int>{};
      for (final e in series) {
        keys.update('${e.targetKey}|${e.length}', (n) => n + 1, ifAbsent: () => 1);
      }
      final key = keys.containsKey('T20|15') ? 'T20|15' : (keys.entries.toList()..sort((a, b) => b.value - a.value)).first.key;
      final parts = key.split('|');
      final best = series.where((e) => '${e.targetKey}|${e.length}' == key).map((e) => e.score).reduce(math.max);
      final label = TrainingTarget.fromKey(parts[0])?.label ?? parts[0];
      out.add(RecordLine('target', 'Record série $label', 'sur ${parts[1]} fléchettes', '$best'));
    }
    final volleys = entries.where((e) => e.volleys && e.best > 0).toList();
    if (volleys.isNotEmpty) {
      final b = volleys.reduce((a, b) => b.best > a.best ? b : a);
      out.add(RecordLine('repeat', 'Meilleure volée libre', dayFr(b.at), '${b.best}'));
    }
    return out;
  }

  ({int total, List<String> darts, DateTime at})? get bestCheckout => _bestCheckout(entries);

  ({int total, List<String> darts, DateTime at})? _bestCheckout(Iterable<StatEntry> es) {
    ({int total, List<String> darts, DateTime at})? best;
    for (final e in es.where((e) => e.x01)) {
      for (final r in e.rows) {
        if (r.checkout && (best == null || r.total > best.total)) best = (total: r.total, darts: r.darts, at: e.at);
      }
    }
    return best;
  }

  /// Manche gagnée en un minimum de fléchettes (501 d'abord).
  ({int start, int darts})? get shortestLeg {
    ({int start, int darts})? best;
    for (final pass in [true, false]) {
      for (final e in entries.where((e) => e.x01 && (!pass || e.startScore == 501))) {
        for (final leg in e.legs) {
          if (leg.isEmpty || !leg.last.checkout) continue;
          final d = leg.fold(0, (n, r) => n + r.darts.length);
          if (best == null || d < best.darts) best = (start: e.startScore, darts: d);
        }
      }
      if (best != null) return best;
    }
    return best;
  }

  // MARK: X01

  late final List<StatEntry> _x01Recent = since(const Duration(days: 30)).where((e) => e.x01).toList();

  List<StatEntry> get x01Period => _x01Recent.isNotEmpty ? _x01Recent : entries.where((e) => e.x01).toList();
  String get x01PeriodLabel => _x01Recent.isNotEmpty ? 'Sur les 30 derniers jours' : 'Depuis le début';

  double? get x01Average => average(x01Period);

  double? get first9 {
    var pts = 0, d = 0;
    for (final e in x01Period) {
      for (final leg in e.legs) {
        for (final r in leg.take(3)) {
          pts += r.bust ? 0 : r.total;
          d += r.darts.length;
        }
      }
    }
    return d == 0 ? null : pts / d * 3;
  }

  double? get dartsPer501 {
    final legs = <int>[];
    for (final e in x01Period.where((e) => e.startScore == 501)) {
      for (final leg in e.legs) {
        if (leg.isNotEmpty && leg.last.checkout) legs.add(leg.fold(0, (n, r) => n + r.darts.length));
      }
    }
    return legs.isEmpty ? null : legs.reduce((a, b) => a + b) / legs.length;
  }

  List<int> get x01Turns => [for (final e in x01Period) ...e.turnScores];

  static const bucketLabels = ['0-19', '20-39', '40-59', '60-79', '80-99', '100+', '140+', '180'];

  static int bucketOf(int s) => s >= 180
      ? 7
      : s >= 140
      ? 6
      : s >= 100
      ? 5
      : math.min(4, s ~/ 20);

  List<int> get buckets {
    final b = List.filled(8, 0);
    for (final s in x01Turns) {
      b[bucketOf(s)]++;
    }
    return b;
  }

  String get bucketsCaption {
    final b = buckets;
    final n = b.fold(0, (a, c) => a + c);
    if (n == 0) return 'Joue au 301 ou au 501 pour voir tes tours.';
    var top = 0;
    for (var i = 1; i < b.length; i++) {
      if (b[i] > b[top]) top = i;
    }
    final pct = (b[top] * 100 / n).round();
    final range = top >= 5 ? 'à ${bucketLabels[top]}' : 'entre ${top * 20} et ${top * 20 + 19}';
    return top < 3 ? "$pct % de tes tours finissent $range. Le 60 de base, c'est pour bientôt." : '$pct % de tes tours finissent $range.';
  }

  /// Réussite par double tenté (sorties), les 6 plus tentés.
  List<DoubleRate> get doubles {
    final tries = <String, int>{}, hits = <String, int>{};
    for (final e in x01Period.where((e) => e.doubleOut)) {
      for (final leg in e.legs) {
        var rem = e.startScore;
        for (final r in leg) {
          var x = rem;
          for (final l in r.darts) {
            final d = parseDart(l);
            String? aim;
            if (x == 50) {
              aim = 'Bull';
            } else if (x > 0 && x <= 40 && x.isEven) {
              aim = 'D${x ~/ 2}';
            }
            if (aim != null) tries.update(aim, (n) => n + 1, ifAbsent: () => 1);
            x -= d.score;
            if (x < 0 || x == 1 || (x == 0 && !d.isDouble)) break;
            if (x == 0) {
              if (aim != null) hits.update(aim, (n) => n + 1, ifAbsent: () => 1);
              break;
            }
          }
          rem = r.rest;
        }
      }
    }
    final list = [for (final k in tries.keys) DoubleRate(k, tries[k]!, hits[k] ?? 0)]
      ..sort((a, b) => b.tries - a.tries);
    return list.take(6).toList()..sort((a, b) => b.pct - a.pct);
  }

  ({int total, List<String> darts, DateTime at})? get x01BestCheckout => _bestCheckout(x01Period);

  // MARK: Entraînement

  List<SeriesCard> get seriesCards => [
    for (final t in TrainingTarget.presets)
      () {
        final es = entries.where((e) => e.target && e.targetKey == t.key && e.length == 15).toList();
        if (es.isEmpty) return SeriesCard(t.label, null, const [], false);
        final best = es.map((e) => e.score).reduce(math.max);
        final first = es.firstWhere((e) => e.score == best);
        final fresh = es.length > 1 && now.difference(first.at).inDays < 7 && es.indexOf(first) > 0;
        final last = [for (final e in es.skip(math.max(0, es.length - 10))) e.score];
        return SeriesCard(t.label, best, last, fresh);
      }(),
  ];

  List<StatEntry> get _volleys => entries.where((e) => e.volleys).toList();
  int? get bestVolley => _volleys.isEmpty ? null : _volleys.map((e) => e.best).reduce(math.max);
  double? get bestVolleyAverage {
    final v = _volleys.where((e) => e.darts > 0).toList();
    return v.isEmpty ? null : v.map((e) => e.score / e.darts * 3).reduce(math.max);
  }

  int get volleysThrown => _volleys.fold(0, (n, e) => n + _int(e.p['volleys']));

  Set<DateTime> get playedDays => {for (final e in entries) _day(e.at)};

  /// Jours d'affilée avec au moins une partie ou une série (aujourd'hui ou hier compris).
  int get streak {
    final days = playedDays;
    var d = _day(now);
    if (!days.contains(d)) d = d.subtract(const Duration(days: 1));
    var n = 0;
    while (days.contains(d)) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  /// Lundi à dimanche de cette semaine : joué ou pas.
  List<bool> get week {
    final m = monday(now), days = playedDays;
    return [for (var i = 0; i < 7; i++) days.contains(m.add(Duration(days: i)))];
  }

  int get weekDarts => between(monday(now), monday(now).add(const Duration(days: 7))).fold(0, (n, e) => n + e.darts);

  // MARK: Potes

  List<Rival> get rivals {
    final out = <String, Rival>{};
    for (final e in entries.where((e) => e.versus)) {
      final winnerIds = {
        for (final o in e.players)
          if (o['won'] == true) o['id'],
      };
      for (final o in e.players) {
        final oid = '${o['id']}';
        if (oid == id) continue;
        final guest = oid.startsWith('guest:');
        final key = guest ? 'guest' : oid;
        final r = out.putIfAbsent(key, () => Rival(guest ? 'Invités' : '${o['name']}'));
        if (!guest) r.name = '${o['name']}';
        final w = e.won ? 1 : 0;
        final l = !e.won && winnerIds.contains(o['id']) ? 1 : 0;
        if (w + l == 0) continue;
        r.wins += w;
        r.losses += l;
        r.lastAt = e.at;
        r.lastMode = e.mode;
        final bm = r.byMode[e.mode] ?? (0, 0);
        r.byMode[e.mode] = (bm.$1 + w, bm.$2 + l);
      }
    }
    return out.values.where((r) => r.games > 0).toList()..sort((a, b) => b.games - a.games);
  }

  /// Le pote qui te bat le plus (au moins 3 parties, plus de défaites que de victoires).
  Rival? get nemesis {
    final c = rivals.where((r) => r.name != 'Invités' && r.games >= 3 && r.losses > r.wins).toList()
      ..sort((a, b) => (b.losses - b.wins) - (a.losses - a.wins));
    return c.firstOrNull;
  }

  /// Le pote que tu bats le plus.
  Rival? get favourite {
    final c = rivals.where((r) => r.name != 'Invités' && r.games >= 3 && r.wins > r.losses).toList()
      ..sort((a, b) => (b.wins - b.losses) - (a.wins - a.losses));
    return c.firstOrNull;
  }

  // MARK: Cible

  static const aims = ['T20', 'T19', 'Doubles'];

  List<StatEntry> seriesFor(String aim) => entries
      .where((e) => e.target && (aim == 'Doubles' ? (e.targetKey ?? '').startsWith('D') : e.targetKey == aim))
      .toList();

  List<({DartThrow dart, double x, double y, TrainingTarget target})> throwsFor(String aim) => [
    for (final e in seriesFor(aim))
      for (final t in e.throws)
        (dart: t.dart, x: t.x, y: t.y, target: TrainingTarget.fromKey(e.targetKey ?? '') ?? TrainingTarget.presets.first),
  ];

  // MARK: Ton mois

  List<StatEntry> month(int year, int m) => entries.where((e) => e.at.year == year && e.at.month == m).toList();

  /// Mois précédent qui a des parties, null sinon.
  (int, int)? previousMonth(int year, int m) {
    final before = entries.where((e) => e.at.isBefore(DateTime(year, m)));
    if (before.isEmpty) return null;
    final l = before.last.at;
    return (l.year, l.month);
  }

  AimReport aimReport(String aim) => AimReport(aim, throwsFor(aim));

  MonthReport monthReport(int year, int m) => MonthReport(this, year, m);
}

/// Ordre des secteurs, en partant du haut, sens horaire (comme le plateau).
const _order = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5];

/// Où tombent les fléchettes quand on vise une cible.
class AimReport {
  AimReport(this.aim, this.all);

  final String aim;
  final List<({DartThrow dart, double x, double y, TrainingTarget target})> all;

  bool get isEmpty => all.isEmpty;
  int get n => all.length;
  bool get doubles => aim == 'Doubles';
  TrainingTarget? get single => doubles ? null : TrainingTarget.fromKey(aim);

  int _pct(int k) => n == 0 ? 0 : (k * 100 / n).round();

  int get exactPct => _pct(all.where((t) => t.target.matches(t.dart)).length);
  int get widePct => _pct(all.where((t) => doubles ? t.dart.isDouble : t.dart.sector == t.target.sector).length);
  String get exactLabel => doubles ? 'Dans le double visé' : 'Dans le $aim';
  String get wideLabel => doubles ? 'Dans un double' : 'Dans le ${single?.sector ?? ''}';

  /// Écart d'angle avec le secteur visé, en degrés (négatif = à gauche).
  static double _delta(double x, double y, int sector) {
    var a = math.atan2(x, -y) * 180 / math.pi;
    if (a < 0) a += 360;
    var d = a - _order.indexOf(sector) * 18;
    while (d > 180) {
      d -= 360;
    }
    while (d <= -180) {
      d += 360;
    }
    return d;
  }

  List<double> get _deltas => [
    for (final t in all)
      if (t.target.sector != 25 && !t.dart.isMiss && math.sqrt(t.x * t.x + t.y * t.y) > 16)
        _delta(t.x, t.y, t.target.sector),
  ];

  int get leftPct => _pct(_deltas.where((d) => d < -9).length);
  int get rightPct => _pct(_deltas.where((d) => d > 9).length);

  /// -1 à gauche, 1 à droite, 0 centré.
  int get side {
    final l = leftPct, r = rightPct;
    if (l >= 10 && l >= r + 8) return -1;
    if (r >= 10 && r >= l + 8) return 1;
    return 0;
  }

  String get title => switch (side) {
    -1 => 'Tu tires à gauche.',
    1 => 'Tu tires à droite.',
    _ => 'Ton lancer est bien centré.',
  };

  String get body {
    final t = single;
    if (t != null && t.sector != 25) {
      final i = _order.indexOf(t.sector);
      final left = _order[(i + 19) % 20], right = _order[(i + 1) % 20];
      return '$leftPct % de tes fléchettes partent dans le $left, $rightPct % dans le $right.';
    }
    return '$leftPct % de tes fléchettes partent à gauche du double visé, $rightPct % à droite.';
  }

  String get advice => switch (side) {
    -1 => "Conseil : décale-toi d'un pas à droite",
    1 => "Conseil : décale-toi d'un pas à gauche",
    _ => 'Conseil : garde ce lancer',
  };

  /// Secteurs touchés, les 5 premiers puis hors cible.
  List<SectorShare> get shares {
    final c = <String, int>{};
    var miss = 0;
    for (final t in all) {
      if (t.dart.isMiss) {
        miss++;
      } else {
        c.update(t.dart.sector == 25 ? 'Bull' : '${t.dart.sector}', (v) => v + 1, ifAbsent: () => 1);
      }
    }
    final top = c.entries.toList()..sort((a, b) => b.value - a.value);
    return [
      for (final e in top.take(5)) SectorShare(e.key, _pct(e.value)),
      if (miss > 0) SectorShare('Hors', _pct(miss)),
    ];
  }

  /// Les deux secteurs les plus touchés (teintés sur le plateau).
  Set<int> get heat => {
    for (final s in shares.take(2))
      if (int.tryParse(s.label) != null) int.parse(s.label) else if (s.label == 'Bull') 25,
  };

  /// Les 15 dernières fléchettes.
  List<({DartThrow dart, double x, double y, TrainingTarget target})> get recent =>
      all.skip(math.max(0, all.length - 15)).toList();
}

/// Le bilan d'un mois.
class MonthReport {
  MonthReport(this.s, this.year, this.month)
    : es = s.month(year, month),
      prev = s.previousMonth(year, month);

  final OwnerStats s;
  final int year, month;
  final List<StatEntry> es;
  final (int, int)? prev;

  String get name => monthsFr[month - 1];
  String? get prevName => prev == null ? null : monthsFr[prev!.$2 - 1];
  bool get isCurrent => year == s.now.year && month == s.now.month;

  double? get avg => average(es);
  double? get prevAvg => prev == null ? null : average(s.month(prev!.$1, prev!.$2));

  /// Moyennes des mois d'avant, les plus hautes d'abord.
  List<(double, int)> get _pastMonths {
    final keys = <(int, int)>{
      for (final e in s.entries)
        if (e.at.isBefore(DateTime(year, month))) (e.at.year, e.at.month),
    };
    return [
      for (final k in keys)
        if (average(s.month(k.$1, k.$2)) != null) (average(s.month(k.$1, k.$2))!, k.$2),
    ]..sort((a, b) => b.$1.compareTo(a.$1));
  }

  ({String label, String big, String line, String caption}) get hero {
    final a = avg, p = prevAvg;
    if (a != null && p != null) {
      final d = a - p;
      final best = _pastMonths.firstOrNull;
      return (
        label: d >= 0 ? 'Ta moyenne a pris' : 'Ta moyenne a perdu',
        big: signed1(d),
        line: 'De ${fr1(p)} à ${fr1(a)} en un mois.',
        caption: best == null || a > best.$1
            ? 'Ton meilleur mois depuis le début.'
            : 'Ton record reste ${fr1(best.$1)}, en ${monthsFr[best.$2 - 1]}.',
      );
    }
    if (a != null) {
      return (
        label: 'Ta moyenne ce mois',
        big: fr1(a),
        line: 'Ton premier mois avec une moyenne.',
        caption: 'Le mois prochain, on compare.',
      );
    }
    final g = es.length;
    return (
      label: 'Ce mois-ci',
      big: '$g',
      line: g == 0 ? 'Pas encore joué.' : (g > 1 ? 'parties et séries.' : 'partie ou série.'),
      caption: g == 0 ? 'La cible attend.' : 'Joue au X01 ou en volées libres pour suivre ta moyenne.',
    );
  }

  int get daysInMonth => DateTime(year, month + 1, 0).day;

  /// Niveau de jeu de chaque jour du mois : 0 rien, 1 un peu, 2 bien, 3 beaucoup.
  List<int> get levels {
    final darts = <int, int>{};
    final played = <int>{};
    for (final e in es) {
      played.add(e.at.day);
      darts.update(e.at.day, (n) => n + e.darts, ifAbsent: () => e.darts);
    }
    return [
      for (var d = 1; d <= daysInMonth; d++)
        !played.contains(d)
            ? 0
            : darts[d]! >= 150
            ? 3
            : darts[d]! >= 60
            ? 2
            : 1,
    ];
  }

  int get daysPlayed => {for (final e in es) e.at.day}.length;

  List<Tile> get tiles {
    final out = <Tile>[];
    final days = daysPlayed;
    final pastMax = <(int, int), Set<int>>{};
    for (final e in s.entries.where((e) => e.at.isBefore(DateTime(year, month)))) {
      pastMax.putIfAbsent((e.at.year, e.at.month), () => {}).add(e.at.day);
    }
    final record = pastMax.isNotEmpty && days > pastMax.values.map((v) => v.length).reduce(math.max);
    out.add(Tile('calendar', 'Jours joués', '$days', 'sur $daysInMonth${record ? ', record battu' : ''}'));

    final darts = es.fold(0, (n, e) => n + e.darts);
    out.add(
      Tile(
        'target',
        'Fléchettes lancées',
        thousands(darts),
        days == 0 ? 'pas encore de soirée' : 'environ ${(darts / days).round()} par soir',
      ),
    );

    final d180 = <int>[];
    for (final e in es) {
      for (final t in e.turnScores) {
        if (t == 180) d180.add(e.at.day);
      }
    }
    final u = d180.toSet().toList()..sort();
    String daysList(List<int> l) {
      final parts = [for (final d in l.take(3)) 'le $d'];
      final j = parts.length <= 1 ? parts.join() : '${parts.take(parts.length - 1).join(', ')} et ${parts.last}';
      return '$j ${monthsShortFr[month - 1]}';
    }

    out.add(Tile('flame', '180 du mois', '${d180.length}', u.isEmpty ? 'pas encore ce mois-ci' : daysList(u)));

    // Meilleure soirée : le plus de victoires, sinon le plus de fléchettes.
    final byDay = <int, List<StatEntry>>{};
    for (final e in es) {
      byDay.putIfAbsent(e.at.day, () => []).add(e);
    }
    if (byDay.isEmpty) {
      out.add(const Tile('trophy', 'Meilleure soirée', 'Aucune', 'joue une partie'));
    } else {
      int wins(List<StatEntry> l) => l.where((e) => e.versus && e.won).length;
      int dd(List<StatEntry> l) => l.fold(0, (n, e) => n + e.darts);
      final best = byDay.entries.reduce(
        (a, b) => wins(b.value) > wins(a.value) || (wins(b.value) == wins(a.value) && dd(b.value) > dd(a.value)) ? b : a,
      );
      final date = DateTime(year, month, best.key);
      final games = best.value.where((e) => !e.drill).length;
      final w = wins(best.value);
      out.add(
        Tile(
          'trophy',
          'Meilleure soirée',
          '${daysShortFr[date.weekday - 1]} ${best.key}',
          w > 0
              ? '$games partie${games > 1 ? 's' : ''}, $w victoire${w > 1 ? 's' : ''}'
              : '${thousands(dd(best.value))} fléchettes',
        ),
      );
    }

    final games = es.where((e) => !e.drill).toList();
    if (games.isEmpty) {
      out.add(
        Tile(
          'layout-grid',
          'Jeu le plus joué',
          es.isEmpty ? 'Aucun' : 'Séries',
          es.isEmpty ? 'pas encore de partie' : "que de l'entraînement",
        ),
      );
    } else {
      final c = <String, int>{};
      for (final e in games) {
        c.update(e.mode, (n) => n + 1, ifAbsent: () => 1);
      }
      final top = c.entries.reduce((a, b) => b.value > a.value ? b : a);
      out.add(Tile('layout-grid', 'Jeu le plus joué', top.key, '${(top.value * 100 / games.length).round()} % de tes parties'));
    }

    final byHour = <int, List<StatEntry>>{};
    for (final e in es) {
      byHour.putIfAbsent(e.at.hour, () => []).add(e);
    }
    final scored = byHour.entries.where((h) => h.value.fold(0, (n, e) => n + e.pointDarts) >= 9).toList();
    if (scored.isNotEmpty) {
      final h = scored.reduce((a, b) => average(b.value)! > average(a.value)! ? b : a);
      out.add(Tile('moon', 'Ton heure', '${h.key} h', 'ta moyenne y est la plus haute'));
    } else if (byHour.isNotEmpty) {
      final h = byHour.entries.reduce((a, b) => b.value.length > a.value.length ? b : a);
      out.add(Tile('moon', 'Ton heure', '${h.key} h', "c'est là que tu joues le plus"));
    } else {
      out.add(const Tile('moon', 'Ton heure', 'Aucune', 'pas encore joué'));
    }
    return out;
  }
}
