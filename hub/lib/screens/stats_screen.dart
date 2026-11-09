import 'dart:math' as math;

import 'package:darts_engine/darts_engine.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../game_config.dart';
import '../history/history_store.dart';
import '../stats/owner_stats.dart';
import '../theme/tokens.dart';
import '../widgets/avatar.dart';
import '../widgets/controls.dart';
import '../widgets/dartboard.dart';
import '../widgets/game_widgets.dart';
import '../widgets/stage.dart';
import '../widgets/td_button.dart';

// Planche "Stats de Thibs Pi" : Résumé, X01, Entraînement, Potes, Cible, et Ton mois.

const _tabs = ['Résumé', 'X01', 'Entraînement', 'Potes', 'Cible'];

IconData _icon(String name) => switch (name) {
  'flame' => LucideIcons.flame,
  'log-out' => LucideIcons.logOut,
  'zap' => LucideIcons.zap,
  'target' => LucideIcons.target,
  'repeat' => LucideIcons.repeat,
  'calendar' => LucideIcons.calendar,
  'trophy' => LucideIcons.trophy,
  'layout-grid' => LucideIcons.layoutGrid,
  'moon' => LucideIcons.moon,
  _ => LucideIcons.circle,
};

/// Panneau des planches : verre léger (0,05) ou moyen (0,09), bord clair, liseré.
BoxDecoration _glass({bool strong = false, double radius = Td.rLg, Color? color, Color? border}) => BoxDecoration(
  color: color ?? (strong ? Td.verreMoyen : Td.verreLeger),
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: border ?? Td.verreBord),
);

Widget _label(String t, {Color color = Td.ink2}) => Text(t, style: TdText.inter(13, 18, 600, color));
Widget _caption(String t, {int lines = 2}) =>
    Text(t, maxLines: lines, overflow: TextOverflow.ellipsis, style: TdText.inter(13, 18, 400, Td.ink3));
Widget _sub(String t) => Text(t, maxLines: 3, overflow: TextOverflow.ellipsis, style: TdText.inter(15, 20, 400, Td.ink2));
Widget _panelTitle(String t) => Text(t, style: TdText.inter(15, 20, 600, Td.ink));

/// Écran des stats du propriétaire, ouvert depuis l'accueil.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, this.history, this.now, this.initialTab = 'Résumé'});

  /// Historique à utiliser (tests), sinon celui du Pi.
  final List<Map<String, Object?>>? history;
  final DateTime? now;
  final String initialTab;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  late final OwnerStats _s = OwnerStats(widget.history ?? HistoryStore.instance.all(), now: widget.now);
  late String _tab = widget.initialTab;
  String _aim = 'T20';

  void _openMonth() => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => MonthStatsScreen(stats: _s, year: _s.now.year, month: _s.now.month)),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Td.beton,
    body: Stage(
      child: Padding(
        padding: const EdgeInsets.all(Td.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 14,
          children: [
            _header(),
            Expanded(
              child: switch (_tab) {
                'X01' => _x01(),
                'Entraînement' => _training(),
                'Potes' => _friends(),
                'Cible' => _target(),
                _ => _summary(),
              },
            ),
          ],
        ),
      ),
    ),
  );

  Widget _header() {
    final title = switch (_tab) {
      'X01' => '301 et 501',
      'Entraînement' => 'Tes records',
      'Potes' => 'Face aux potes',
      'Cible' => 'Où tombent tes fléchettes',
      _ => null,
    };
    return Row(
      children: [
        TdIconButton(icon: LucideIcons.chevronLeft, label: 'Retour', onPressed: () => Navigator.of(context).pop()),
        const SizedBox(width: Td.s3),
        if (title == null) ...[
          Avatar(name: AppState.owner, size: 48, active: true),
          const SizedBox(width: Td.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(AppState.owner, maxLines: 1, overflow: TextOverflow.ellipsis, style: TdText.headline),
                Text(
                  _s.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TdText.inter(13, 18, 400, Td.ink2),
                ),
              ],
            ),
          ),
        ] else
          Expanded(
            child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TdText.headline),
          ),
        const SizedBox(width: Td.s3),
        SizedBox(
          width: 580,
          child: TdSegmented(options: _tabs, value: _tab, touch: true, onChanged: (v) => setState(() => _tab = v)),
        ),
      ],
    );
  }

  // MARK: Résumé

  Widget _summary() {
    final avg = _s.averageNow;
    final co = _s.checkoutPct;
    final win = _s.winPct;
    final m180 = _s.month180;
    final records = _s.records;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 14,
      children: [
        Row(
          spacing: 10,
          children: [
            Expanded(
              child: GestureDetector(
                onTap: _openMonth,
                child: KpiTile(label: 'Moyenne 3 fléchettes', value: avg == null ? '0' : fr1(avg), unit: _s.averageTrend),
              ),
            ),
            Expanded(
              child: KpiTile(label: 'Checkout', value: co == null ? '0' : '$co', unit: '%'),
            ),
            Expanded(
              child: KpiTile(
                label: '180 au total',
                value: '${_s.total180}',
                unit: m180 > 0 ? 'dont $m180 ce mois' : null,
              ),
            ),
            Expanded(
              child: KpiTile(label: 'Parties gagnées', value: win == null ? '0' : '$win', unit: '%'),
            ),
          ],
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  decoration: _glass(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 8,
                    children: [
                      Row(
                        children: [
                          Expanded(child: _panelTitle('Ta moyenne, semaine après semaine')),
                          Pressable(
                            onTap: _openMonth,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: Td.s1),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                spacing: 2,
                                children: [
                                  Text('Ton mois', style: TdText.inter(13, 18, 600, Td.sunset)),
                                  const Icon(LucideIcons.chevronRight, size: 16, color: Td.sunset),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: _openMonth,
                          child: CustomPaint(painter: _WeeklyPainter(_s.weekly), size: Size.infinite),
                        ),
                      ),
                      Text(_s.weeklyCaption, style: TdText.inter(13, 18, 400, Td.ink2)),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: 320,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 8,
                  children: [
                    _label('Records'),
                    if (records.isEmpty)
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(Td.s4),
                          decoration: _glass(radius: Td.rMd),
                          alignment: Alignment.center,
                          child: _sub('Joue une partie ou une série, tes records arrivent ici.'),
                        ),
                      ),
                    for (final r in records.take(5))
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: _glass(radius: Td.rMd),
                          child: Row(
                            spacing: 12,
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: Td.asphalteHaut,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(_icon(r.icon), size: 20, color: Td.sunset),
                              ),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      r.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TdText.inter(15, 20, 600, Td.ink),
                                    ),
                                    Text(
                                      r.when,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TdText.inter(12, 16, 400, Td.ink3),
                                    ),
                                  ],
                                ),
                              ),
                              Text(r.value, style: TdText.rounded(26, 900, Td.ink, height: 28)),
                            ],
                          ),
                        ),
                      ),
                    if (records.isNotEmpty)
                      for (var i = records.length; i < 5; i++) const Expanded(child: SizedBox()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // MARK: X01

  Widget _x01() {
    final avg = _s.x01Average;
    final f9 = _s.first9;
    final per = _s.dartsPer501;
    final b = _s.buckets;
    final turns = b.fold(0, (a, c) => a + c);
    final doubles = _s.doubles;
    final out = _s.x01BestCheckout;
    final c100 = b[5], c140 = b[6], c180 = b[7];
    Widget counter(String label, int v, {bool hot = false}) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: _glass(radius: Td.rMd, color: hot ? Td.sunsetFond : null, border: hot ? Td.sunset : null),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 2,
          children: [
            Text(label, style: TdText.inter(12, 16, hot ? 600 : 400, hot ? Td.sunset : Td.ink2)),
            Text('$v', style: TdText.rounded(30, 900, Td.ink, height: 32)),
          ],
        ),
      ),
    );
    final maxPct = turns == 0 ? 1.0 : b.reduce(math.max) * 100 / turns;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        SizedBox(
          width: 260,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ScoreDisplay(
                value: 0,
                text: avg == null ? '0' : fr1(avg),
                label: 'Moyenne 3 fléchettes',
                sub: _s.x01PeriodLabel,
              ),
              Row(
                spacing: 8,
                children: [
                  Expanded(child: KpiTile(label: '9 premières', value: f9 == null ? '0' : fr1(f9))),
                  Expanded(
                    child: KpiTile(label: 'Fléchettes par 501', value: per == null ? '0' : '${per.round()}'),
                  ),
                ],
              ),
              Row(
                spacing: 8,
                children: [counter('100+', c100), counter('140+', c140), counter('180', c180, hot: true)],
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(Td.s4),
            decoration: _glass(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: [
                Row(
                  children: [
                    Expanded(child: _panelTitle('Tes tours, par score')),
                    _caption('${thousands(turns)} tour${turns > 1 ? 's' : ''}', lines: 1),
                  ],
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final barMax = math.max(4.0, c.maxHeight - 50);
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        spacing: 8,
                        children: [
                          for (var i = 0; i < 8; i++)
                            () {
                              final p = turns == 0 ? 0.0 : b[i] * 100 / turns;
                              final top = turns > 0 && b[i] == b.reduce(math.max);
                              final color = i == 7 ? Td.fluo : (top ? Td.sunset : const Color(0x73FF7A2F));
                              final txt = p == 0 ? '0 %' : (p < 10 ? '${fr1(p)} %' : '${p.round()} %');
                              return Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  spacing: 6,
                                  children: [
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(txt, style: TdText.inter(12, 16, 600, Td.ink)),
                                    ),
                                    Container(
                                      height: math.max(4, p / maxPct * barMax),
                                      decoration: BoxDecoration(
                                        color: color,
                                        borderRadius: const BorderRadius.vertical(
                                          top: Radius.circular(8),
                                          bottom: Radius.circular(3),
                                        ),
                                      ),
                                    ),
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        OwnerStats.bucketLabels[i],
                                        style: TdText.inter(11, 14, 400, Td.ink3),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }(),
                        ],
                      );
                    },
                  ),
                ),
                Text(_s.bucketsCaption, style: TdText.inter(13, 18, 400, Td.ink2)),
              ],
            ),
          ),
        ),
        SizedBox(
          width: 300,
          child: Container(
            padding: const EdgeInsets.all(Td.s4),
            decoration: _glass(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: [
                Row(
                  children: [
                    Expanded(child: _panelTitle('Sorties, par double')),
                    _caption('réussite', lines: 1),
                  ],
                ),
                if (doubles.isEmpty) _sub('Termine une partie sur un double pour voir tes sorties.'),
                for (final (i, d) in doubles.indexed)
                  _bar(
                    d.label,
                    d.pct / 100,
                    '${d.pct} %',
                    i == 0 ? Td.succes : (d.pct < 30 ? Td.erreur : Td.ciel),
                    height: 10,
                    labelWidth: 40,
                  ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(Td.s3),
                  decoration: _glass(radius: Td.rMd),
                  child: Row(
                    spacing: 12,
                    children: [
                      Text(
                        out == null ? '0' : '${out.total}',
                        style: TdText.rounded(34, 900, Td.sunset, height: 36),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Meilleure sortie', style: TdText.inter(13, 18, 600, Td.ink)),
                            Text(
                              out == null ? 'pas encore de sortie' : out.darts.join(', '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TdText.inter(12, 16, 400, Td.ink3),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Ligne "libellé, barre, pourcentage" (doubles, secteurs).
  Widget _bar(String label, double frac, String pct, Color color, {double height = 12, double labelWidth = 28}) => Row(
    spacing: 10,
    children: [
      SizedBox(
        width: labelWidth,
        child: Text(label, style: TdText.rounded(17, 900, Td.ink)),
      ),
      Expanded(
        child: Container(
          height: height,
          decoration: BoxDecoration(color: Td.verreMoyen, borderRadius: BorderRadius.circular(height / 2)),
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: frac.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(height / 2)),
            ),
          ),
        ),
      ),
      SizedBox(
        width: 40,
        child: Text(pct, textAlign: TextAlign.right, style: TdText.inter(13, 18, 600, Td.ink)),
      ),
    ],
  );

  // MARK: Entraînement

  Widget _training() {
    final cards = _s.seriesCards;
    final bv = _s.bestVolley;
    final ba = _s.bestVolleyAverage;
    final streak = _s.streak;
    final week = _s.week;
    const days = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              Row(
                children: [
                  Expanded(child: _label('Séries sur cible, 15 fléchettes')),
                  _caption('courbe : tes 10 dernières séries', lines: 1),
                ],
              ),
              Expanded(
                child: Column(
                  spacing: 10,
                  children: [
                    for (var row = 0; row < 2; row++)
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 10,
                          children: [for (var i = row * 3; i < row * 3 + 3; i++) Expanded(child: _seriesCard(cards[i]))],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 300,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              Container(
                padding: const EdgeInsets.all(Td.s4),
                decoration: _glass(strong: true),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 10,
                  children: [
                    _panelTitle('Volées libres'),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      spacing: 8,
                      children: [
                        Text(bv == null ? '0' : '$bv', style: TdText.rounded(64, 900, Td.sunset, height: 64)),
                        Text('meilleure volée', style: TdText.inter(13, 18, 400, Td.ink2)),
                      ],
                    ),
                    Row(
                      spacing: 8,
                      children: [
                        Expanded(child: KpiTile(label: 'Meilleure moyenne', value: ba == null ? '0' : fr1(ba))),
                        Expanded(child: KpiTile(label: 'Volées tirées', value: thousands(_s.volleysThrown))),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(Td.s4),
                  decoration: _glass(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 2,
                        children: [
                          _panelTitle(
                            streak == 0
                                ? 'Pas de série en cours'
                                : (streak == 1 ? '1 jour de suite' : "$streak jours d'affilée"),
                          ),
                          Text('Une série par jour. Sans forcer.', style: TdText.inter(13, 18, 400, Td.ink2)),
                        ],
                      ),
                      Row(
                        spacing: 6,
                        children: [
                          for (var i = 0; i < 7; i++)
                            Expanded(
                              child: Column(
                                spacing: 4,
                                children: [
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: week[i] ? Td.sunset : Td.verreLeger,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: week[i] ? Td.sunset : Td.verreBord),
                                    ),
                                  ),
                                  Text(days[i], style: TdText.inter(11, 14, 400, Td.ink3)),
                                ],
                              ),
                            ),
                        ],
                      ),
                      _caption('Fléchettes cette semaine : ${thousands(_s.weekDarts)}', lines: 1),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _seriesCard(SeriesCard c) {
    final fresh = c.fresh;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _glass(color: fresh ? Td.sunsetFond : null, border: fresh ? Td.sunset : null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Expanded(child: Text(c.label, style: TdText.rounded(24, 900, Td.ink, height: 26))),
              if (fresh) const _Badge('Nouveau'),
            ],
          ),
          SizedBox(
            height: 48,
            child: c.last.length < 2
                ? Center(child: _caption(c.best == null ? 'Pas encore tentée' : 'Une seule série', lines: 1))
                : CustomPaint(
                    painter: _SparkPainter(c.last, fresh ? Td.sunset : Td.ciel),
                    size: Size.infinite,
                  ),
          ),
          if (c.best == null)
            const SizedBox(height: 40)
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              spacing: 6,
              children: [
                Text('${c.best}', style: TdText.rounded(40, 900, Td.ink, height: 40)),
                Text('sur 15, record', style: TdText.inter(13, 18, 400, Td.ink2)),
              ],
            ),
        ],
      ),
    );
  }

  // MARK: Potes

  Widget _friends() {
    final rivals = _s.rivals.take(5).toList();
    final nem = _s.nemesis, fav = _s.favourite;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        SizedBox(
          width: 340,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              Expanded(
                child: _rivalCard(
                  color: Td.erreur,
                  fond: Td.erreurFond,
                  icon: LucideIcons.skull,
                  title: 'Ta bête noire',
                  r: nem,
                  line: nem == null ? '' : 'Te bat ${nem.losses} fois sur ${nem.games}.',
                  caption: nem == null ? '' : _worstMode(nem),
                  empty: "Personne ne te domine. Pour l'instant.",
                ),
              ),
              Expanded(
                child: _rivalCard(
                  color: Td.succes,
                  fond: Td.succesFond,
                  icon: LucideIcons.trophy,
                  title: 'Ton client préféré',
                  r: fav,
                  line: fav == null
                      ? ''
                      : '${fav.wins} victoire${fav.wins > 1 ? 's' : ''}, ${fav.losses} défaite${fav.losses > 1 ? 's' : ''}.',
                  caption: fav == null ? '' : _sentence('Dernière partie : ${fav.lastMode}, ${dayFr(fav.lastAt!)}'),
                  empty: 'Gagne quelques parties contre un pote pour le voir ici.',
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(Td.s4),
            decoration: _glass(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 8,
              children: [
                Row(
                  children: [
                    Expanded(child: _panelTitle('Bilan, pote par pote')),
                    _legend(Td.sunset, 'Tu gagnes'),
                    const SizedBox(width: 14),
                    _legend(Td.ciel, 'Il ou elle gagne'),
                  ],
                ),
                if (rivals.isEmpty)
                  Expanded(
                    child: Center(child: _sub('Joue contre des potes pour voir qui tient la cible.')),
                  ),
                for (final r in rivals)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: _glass(radius: Td.rMd),
                      child: Row(
                        spacing: 14,
                        children: [
                          Avatar(name: r.name, size: 44),
                          SizedBox(
                            width: 120,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TdText.inter(17, 22, 600, Td.ink),
                                ),
                                Text(
                                  r.name == 'Invités'
                                      ? 'toutes les soirées'
                                      : '${dayFr(r.lastAt!).substring(3)}, ${r.lastMode}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TdText.inter(12, 16, 400, Td.ink3),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(7),
                              child: SizedBox(
                                height: 14,
                                child: Row(
                                  spacing: 2,
                                  children: [
                                    if (r.wins > 0) Expanded(flex: r.wins, child: Container(color: Td.sunset)),
                                    if (r.losses > 0) Expanded(flex: r.losses, child: Container(color: Td.ciel)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 76,
                            child: Text(
                              '${r.wins} - ${r.losses}',
                              textAlign: TextAlign.right,
                              style: TdText.rounded(22, 900, Td.ink),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (rivals.isNotEmpty)
                  for (var i = rivals.length; i < 5; i++) const Expanded(child: SizedBox()),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _worstMode(Rival r) {
    final m = r.byMode.entries.where((e) => e.value.$2 > e.value.$1).toList()
      ..sort((a, b) => (b.value.$2 - b.value.$1) - (a.value.$2 - a.value.$1));
    if (m.isEmpty) return _sentence('Dernière partie : ${r.lastMode}, ${dayFr(r.lastAt!)}');
    final mode = m.first.key;
    return 'Surtout au $mode.';
  }

  Widget _legend(Color c, String t) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 6,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
      ),
      Text(t, style: TdText.inter(12, 16, 400, Td.ink2)),
    ],
  );

  Widget _rivalCard({
    required Color color,
    required Color fond,
    required IconData icon,
    required String title,
    required Rival? r,
    required String line,
    required String caption,
    required String empty,
  }) => Container(
    padding: const EdgeInsets.all(18),
    decoration: _glass(color: fond, border: color),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          spacing: 8,
          children: [
            Icon(icon, size: 20, color: color),
            Text(title, style: TdText.inter(13, 18, 600, color)),
          ],
        ),
        if (r == null)
          _sub(empty)
        else
          Row(
            spacing: 14,
            children: [
              Avatar(name: r.name, size: 64),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TdText.inter(28, 34, 700, Td.ink),
                    ),
                    Text(line, style: TdText.inter(15, 20, 400, Td.ink2)),
                  ],
                ),
              ),
            ],
          ),
        Text(
          r == null ? '' : caption,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TdText.inter(13, 18, 400, Td.ink2),
        ),
      ],
    ),
  );

  // MARK: Cible

  Widget _target() {
    final a = _s.aimReport(_aim);
    final t = a.single;
    final shares = a.shares;
    final maxShare = shares.isEmpty ? 1 : shares.map((s) => s.pct).reduce(math.max);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        SizedBox(
          width: 280,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              _label('Quand tu vises'),
              TdSegmented(
                options: OwnerStats.aims,
                value: _aim,
                touch: true,
                onChanged: (v) => setState(() => _aim = v),
              ),
              Container(
                padding: const EdgeInsets.all(Td.s4),
                decoration: _glass(strong: true),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 6,
                  children: [
                    _label(a.isEmpty ? 'Pas encore de données' : 'Ton défaut'),
                    if (a.isEmpty)
                      _sub('Fais une série sur ${a.doubles ? 'un double' : 'le $_aim'} pour voir où tombent tes fléchettes.')
                    else ...[
                      Text(a.title, style: TdText.headline),
                      _sub(a.body),
                    ],
                  ],
                ),
              ),
              Row(
                spacing: 8,
                children: [
                  Expanded(child: KpiTile(label: a.exactLabel, value: '${a.exactPct}', unit: '%')),
                  Expanded(child: KpiTile(label: a.wideLabel, value: '${a.widePct}', unit: '%')),
                ],
              ),
              const Spacer(),
              Row(
                spacing: 8,
                children: [
                  const Icon(LucideIcons.camera, size: 16, color: Td.ink3),
                  Expanded(child: _caption('Positions vues par les 3 caméras.', lines: 1)),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              final side = math.min(470.0, math.min(c.maxWidth, c.maxHeight));
              return Center(
                child: SizedBox(
                  width: side,
                  height: side,
                  child: Dartboard(
                    hits: [
                      for (final (i, h) in a.recent.indexed) BoardHit(h.dart, Offset(h.x, h.y), i + 1),
                    ],
                    aimed: t == null || t.sector == 25 ? null : DartThrow(t.sector, t.multiplier),
                    heat: a.heat,
                  ),
                ),
              );
            },
          ),
        ),
        SizedBox(
          width: 260,
          child: Container(
            padding: const EdgeInsets.all(Td.s4),
            decoration: _glass(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 8,
              children: [
                _panelTitle('Secteurs touchés'),
                Text(
                  'en visant ${a.doubles ? 'les doubles' : 'le $_aim'}, ${a.n} fléchette${a.n > 1 ? 's' : ''}',
                  style: TdText.inter(12, 16, 400, Td.ink3),
                ),
                if (shares.isEmpty) _sub('Rien pour le moment.'),
                for (final (i, s) in shares.indexed)
                  _bar(
                    s.label,
                    s.pct / maxShare,
                    '${s.pct} %',
                    i == 0 ? Td.sunset : (i == 1 ? Td.ciel : const Color(0x59FFFFFF)),
                    labelWidth: 44,
                  ),
                const Spacer(),
                if (!a.isEmpty) _Badge(a.advice),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Badge sunset (composant Badge, ton sunset).
class _Badge extends StatelessWidget {
  const _Badge(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: Td.sunsetFond,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: Td.sunset),
    ),
    child: Text(text, style: TdText.inter(12, 16, 600, Td.sunset)),
  );
}

/// Courbe des 12 dernières semaines (aire dégradée, ligne sunset, point fluo).
class _WeeklyPainter extends CustomPainter {
  _WeeklyPainter(this.weeks);
  final List<({DateTime start, double? avg})> weeks;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 16.0, right = 40.0, bottom = 22.0, top = 10.0;
    final w = size.width - left - right;
    final h = size.height - bottom - top;
    final base = top + h;
    final axis = Paint()
      ..color = Td.verreBord
      ..strokeWidth = 1;
    canvas.drawLine(Offset(left, base), Offset(left + w, base), axis);
    final vals = [for (final x in weeks) x.avg].whereType<double>().toList();
    final xs = [for (var i = 0; i < weeks.length; i++) left + w * i / (weeks.length - 1)];

    void text(String t, Offset o, {Color color = Td.ink3}) {
      final tp = TextPainter(
        text: TextSpan(text: t, style: TdText.inter(11, 14, 400, color)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, o);
    }

    // Mois sous l'axe, à la première semaine de chaque mois.
    int? lastMonth;
    for (var i = 0; i < weeks.length; i++) {
      final m = weeks[i].start.add(const Duration(days: 3)).month;
      if (m != lastMonth && (i == 0 || i < weeks.length - 1)) {
        if (lastMonth == null || i >= 2) text(monthsShortFr[m - 1], Offset(xs[i], base + 6));
        lastMonth = m;
      }
    }
    if (vals.isEmpty) return;
    var lo = vals.reduce(math.min), hi = vals.reduce(math.max);
    if (hi - lo < 6) {
      final mid = (hi + lo) / 2;
      lo = mid - 3;
      hi = mid + 3;
    }
    lo -= (hi - lo) * 0.25;
    hi += (hi - lo) * 0.1;
    double y(double v) => base - (v - lo) / (hi - lo) * h;

    // Deux repères pointillés.
    final step = ((hi - lo) / 3).ceilToDouble();
    final dash = Paint()
      ..color = const Color(0x14FFFFFF)
      ..strokeWidth = 1;
    for (var k = 1; k <= 2; k++) {
      final v = (lo + step * k).roundToDouble();
      final yy = y(v);
      for (var x = left; x < left + w; x += 10) {
        canvas.drawLine(Offset(x, yy), Offset(math.min(x + 4, left + w), yy), dash);
      }
      text('${v.round()}', Offset(left + w + 6, yy - 7));
    }

    final pts = [
      for (var i = 0; i < weeks.length; i++)
        if (weeks[i].avg != null) Offset(xs[i], y(weeks[i].avg!)),
    ];
    if (pts.length > 1) {
      final area = Path()..moveTo(pts.first.dx, base);
      for (final p in pts) {
        area.lineTo(p.dx, p.dy);
      }
      area
        ..lineTo(pts.last.dx, base)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x59FF7A2F), Color(0x00FF7A2F)],
          ).createShader(Rect.fromLTWH(0, top, size.width, h)),
      );
      final line = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final p in pts.skip(1)) {
        line.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        line,
        Paint()
          ..color = Td.sunset
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.drawCircle(pts.last, 8.5, Paint()..color = Td.beton);
    canvas.drawCircle(pts.last, 7, Paint()..color = Td.fluo);
  }

  @override
  bool shouldRepaint(_WeeklyPainter old) => old.weeks != weeks;
}

/// Petite courbe des dernières séries (sur 15).
class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color);
  final List<int> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    final path = Path();
    for (var i = 0; i < n; i++) {
      final x = 4 + (size.width - 8) * i / (n - 1);
      final y = size.height - 4 - values[i].clamp(0, 15) / 15 * (size.height - 8);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.values != values || old.color != color;
}

// MARK: Ton mois

/// "Ton mois de novembre" : progression, jours joués, temps forts.
class MonthStatsScreen extends StatelessWidget {
  const MonthStatsScreen({super.key, required this.stats, required this.year, required this.month});

  final OwnerStats stats;
  final int year, month;

  @override
  Widget build(BuildContext context) {
    final r = stats.monthReport(year, month);
    final hero = r.hero;
    final levels = r.levels;
    final tiles = r.tiles;
    const shade = [Color(0x0FFFFFFF), Color(0x4DFF7A2F), Color(0x99FF7A2F), Td.sunset];
    void go(int y, int m) => Navigator.of(
      context,
    ).pushReplacement(PageRouteBuilder<void>(pageBuilder: (_, _, _) => MonthStatsScreen(stats: stats, year: y, month: m)));
    final next = month == 12 ? (year + 1, 1) : (year, month + 1);
    return Scaffold(
      backgroundColor: Td.beton,
      body: Stage(
        child: Padding(
          padding: const EdgeInsets.all(Td.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 14,
            children: [
              Row(
                spacing: 12,
                children: [
                  TdIconButton(
                    icon: LucideIcons.chevronLeft,
                    label: 'Retour',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Text(
                      'Ton mois ${RegExp('^[aeiouéo]').hasMatch(r.name) ? "d'" : 'de '}${r.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TdText.headline,
                    ),
                  ),
                  if (r.prev != null)
                    SizedBox(
                      width: 220,
                      child: TdButton(
                        label: _cap(r.prevName!),
                        icon: LucideIcons.chevronLeft,
                        variant: TdButtonVariant.secondary,
                        height: Td.ciblePi,
                        onPressed: () => go(r.prev!.$1, r.prev!.$2),
                      ),
                    ),
                  if (!r.isCurrent)
                    SizedBox(
                      width: 220,
                      child: TdButton(
                        label: _cap(monthsFr[next.$2 - 1]),
                        icon: LucideIcons.chevronRight,
                        variant: TdButtonVariant.secondary,
                        height: Td.ciblePi,
                        onPressed: () => go(next.$1, next.$2),
                      ),
                    ),
                ],
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 12,
                  children: [
                    SizedBox(
                      width: 400,
                      child: Container(
                        padding: const EdgeInsets.all(Td.s6),
                        decoration: BoxDecoration(
                          color: Td.verreMoyen,
                          borderRadius: BorderRadius.circular(Td.rXl),
                          border: Border.all(color: Td.verreBord),
                          boxShadow: const [
                            BoxShadow(color: Color(0x38FF7A2F), blurRadius: 48, blurStyle: BlurStyle.outer),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _label(hero.label),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              spacing: 6,
                              children: [
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: ShaderMask(
                                    blendMode: BlendMode.srcIn,
                                    shaderCallback: (b) => Td.goldenHour.createShader(b),
                                    child: Text(
                                      hero.big,
                                      style: TdText.rounded(
                                        140,
                                        900,
                                        Td.ink,
                                        height: 132,
                                      ).copyWith(letterSpacing: -4),
                                    ),
                                  ),
                                ),
                                Text(hero.line, style: TdText.headline),
                                _sub(hero.caption),
                              ],
                            ),
                            LayoutBuilder(
                              builder: (context, c) {
                                const gap = 5.0;
                                final cell = (c.maxWidth - gap * 9) / 10;
                                return Wrap(
                                  spacing: gap,
                                  runSpacing: gap,
                                  children: [
                                    for (final l in levels)
                                      Container(
                                        width: cell,
                                        height: cell,
                                        decoration: BoxDecoration(
                                          color: shade[l],
                                          borderRadius: BorderRadius.circular(5),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        spacing: 10,
                        children: [
                          for (var row = 0; row < 3; row++)
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                spacing: 10,
                                children: [
                                  for (var i = row * 2; i < row * 2 + 2; i++) Expanded(child: _tile(tiles[i])),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _cap(String s) => s[0].toUpperCase() + s.substring(1);

  Widget _tile(Tile t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: _glass(),
    child: Row(
      spacing: 14,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(color: Td.asphalteHaut, borderRadius: BorderRadius.circular(14)),
          child: Icon(_icon(t.icon), size: 24, color: Td.sunset),
        ),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TdText.inter(13, 18, 600, Td.ink2)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(t.value, style: TdText.rounded(30, 900, Td.ink, height: 34)),
              ),
              Text(t.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TdText.inter(12, 16, 400, Td.ink3)),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Termine une phrase par un point, sans doubler celui d'une abréviation ("nov.").
String _sentence(String s) => s.endsWith('.') ? s : '$s.';
