import 'dart:async';

import 'package:darts_engine/darts_engine.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../cam/cam_link.dart';
import '../game_config.dart';
import '../history/history_store.dart';
import '../theme/tokens.dart';
import '../widgets/celebration.dart';
import '../widgets/dartboard.dart';
import '../widgets/game_widgets.dart';
import '../widgets/hit_tag.dart';
import '../widgets/player_card.dart';
import '../widgets/stage.dart';
import '../widgets/td_button.dart';
import 'correction_screen.dart';

/// Record d'un entraînement dans l'historique (meilleur score), null si jamais joué.
int? trainerRecord(String name, GameMode mode, int option) {
  final id = HistoryStore.playerId(name);
  int? best;
  for (final m in HistoryStore.instance.all()) {
    if (m['kind'] != mode.name || ((m['option'] as num?)?.toInt() ?? 0) != option) continue;
    for (final p in m['players'] as List) {
      final pm = p as Map;
      if (pm['id'] != id) continue;
      final h = (pm['score'] as num?)?.toInt();
      if (h != null && (best == null || h > best)) best = h;
    }
  }
  return best;
}

/// Entraînements solo (planches Catch 40 à Cricket Count Up) : joueur et progression à gauche,
/// plateau au centre, score et fléchettes à droite. Toucher le plateau lance une fléchette à cet endroit.
class TrainerScreen extends StatefulWidget {
  const TrainerScreen({super.key, required this.config, this.game});

  final GameConfig config;

  /// Entraînement déjà commencé (captures et tests).
  final TurnGame? game;

  @override
  State<TrainerScreen> createState() => _TrainerScreenState();
}

class _TrainerScreenState extends State<TrainerScreen> {
  late TurnGame _g = widget.game ?? _newGame();
  final List<BoardHit> _hits = [];
  DartThrow? _tagDart;
  int _tagKey = 0;
  Timer? _tagTimer;
  Timer? _endTimer;
  bool _showEnd = false;
  bool _saved = false;
  int? _record;

  GameConfig get _cfg => widget.config;
  GameMode get _mode => _cfg.mode!;
  String get _name => _cfg.players.isEmpty ? AppState.owner : _cfg.players.first;
  int get _option => _cfg.option;

  TurnGame _newGame() => switch (_mode) {
    GameMode.catch40 => LadderGame.catch40(_name),
    GameMode.fortyOne => LadderGame.fortyOne(_name),
    GameMode.nineDarts => CheckoutDrill.nineDarts(_name, start: _option == 81 ? 81 : 121),
    GameMode.ton70 => CheckoutDrill.ton70(_name),
    GameMode.randomCheckout => CheckoutDrill.random(
      _name,
      range: CheckoutRange.values[_option.clamp(0, CheckoutRange.values.length - 1)],
    ),
    GameMode.jdc => JdcGame(_name),
    GameMode.darts99 => Darts99Game(_name, sector: _option == 0 ? 20 : _option),
    GameMode.roundTheWorld => RoundTheWorldGame(_name, multiplier: _option.clamp(1, 3)),
    GameMode.countUp => VolleyGame(_name, volleys: _option == 0 ? 8 : _option),
    GameMode.cricketCountUp => CricketCountUpGame(_name),
    final m => throw ArgumentError('$m n’est pas un entraînement solo'),
  };

  @override
  void initState() {
    super.initState();
    AppState.lastGame = widget.config;
    _record = trainerRecord(_name, _mode, _option);
    CamLink.instance
      ..onDart = _camDart
      ..onTakeout = _camTakeout
      ..setPlaying(true);
  }

  @override
  void dispose() {
    _tagTimer?.cancel();
    _endTimer?.cancel();
    _save();
    if (CamLink.instance.onDart == _camDart) {
      CamLink.instance
        ..onDart = null
        ..onTakeout = null
        ..setPlaying(false);
    }
    super.dispose();
  }

  int get _score => _g.scoreOf(0);
  bool get _newRecord => _g.isFinished && _score > 0 && (_record == null || _score > _record!);

  void _camDart(DartThrow d, Offset? pos) {
    if (mounted) _throw(d, pos ?? boardPositionFor(d));
  }

  void _camTakeout() {
    if (mounted && _g.awaitingNextPlayer && !_g.isFinished) _nextVolley();
  }

  void _throw(DartThrow d, Offset pos) {
    if (_g.awaitingNextPlayer || _g.isFinished) return;
    setState(() {
      _g.throwDart(d);
      _hits.add(BoardHit(d, pos, _hits.length + 1));
      _tagDart = d;
      _tagKey++;
    });
    _tagTimer?.cancel();
    _tagTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _tagDart = null);
    });
    _scheduleEnd();
  }

  void _scheduleEnd() {
    _endTimer?.cancel();
    if (!_g.isFinished) {
      _showEnd = false;
      return;
    }
    AppState.lastResult = '$_name : $_resultLine';
    _endTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted && _g.isFinished) setState(() => _showEnd = true);
    });
  }

  void _onBoardTap(Offset p) => _throw(dartAt(p), p);

  void _outOfBoard() => _throw(const DartThrow.miss(), const Offset(38.7, 181.9));

  Future<void> _correct() async {
    if (_showEnd) return;
    final c = await Navigator.of(context).push<Correction>(
      MaterialPageRoute(
        builder: (_) => CorrectionScreen(turn: _g.currentTurn, hits: List.of(_hits)),
      ),
    );
    if (c == null || !mounted) return;
    setState(() {
      _g.correctDart(c.index, c.dart);
      final kept = <BoardHit>[];
      for (var i = 0; i < _g.currentTurn.length; i++) {
        final d = _g.currentTurn[i];
        final old = i < _hits.length ? _hits[i] : null;
        kept.add(old != null && old.dart == d ? old : BoardHit(d, boardPositionFor(d), i + 1));
      }
      _hits
        ..clear()
        ..addAll(kept);
      _tagDart = null;
    });
    _scheduleEnd();
  }

  void _nextVolley() {
    if (_g.isFinished) {
      setState(() => _showEnd = true);
      return;
    }
    setState(() {
      _g.nextPlayer();
      _hits.clear();
      _tagDart = null;
    });
  }

  void _again() {
    _endTimer?.cancel();
    _save();
    _saved = false;
    setState(() {
      _record = trainerRecord(_name, _mode, _option);
      _g = _newGame();
      _hits.clear();
      _tagDart = null;
      _showEnd = false;
    });
  }

  static String _fr(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

  // MARK: Historique

  void _save() {
    final g = _g;
    if (!g.isFinished || _saved) return;
    _saved = true;
    final turns = g.turnsOf(0);
    final darts = turns.fold<int>(0, (n, t) => n + t.length);
    final (value, label) = _value;
    HistoryStore.instance.add({
      'id': '${DateTime.now().millisecondsSinceEpoch}',
      'at': DateTime.now().toIso8601String(),
      'mode': _cfg.title,
      'kind': _mode.name,
      'training': true,
      'option': _option,
      'winner': null,
      'players': [
        {
          'id': HistoryStore.playerId(_name),
          'name': _name,
          'won': false,
          'darts': darts,
          'score': _score,
          'value': value,
          'valueLabel': label,
          if (g is VolleyGame) 'scores': List.of(g.scores),
          if (g is LadderGame) 'results': List.of(g.results),
          if (g is CheckoutDrill) 'results': [for (final r in g.results) r ? 1 : 0],
          if (g is RoundTheWorldGame) 'results': List.of(g.points),
          if (g is CricketCountUpGame) 'results': List.of(g.perVolley),
          if (g is Darts99Game) 'counts': List.of(g.counts),
        },
      ],
    });
  }

  /// Valeur affichée dans l'historique et sa légende.
  (double, String) get _value => switch (_g) {
    final LadderGame l => (l.total.toDouble(), 'pts'),
    final CheckoutDrill c => (c.successes.toDouble(), 'sur ${c.attempts}'),
    final Darts99Game d => (double.parse(d.average.toStringAsFixed(1)), 'moy.'),
    final VolleyGame v => (v.total.toDouble(), 'pts'),
    final CricketCountUpGame c => (c.total.toDouble(), 'marques'),
    final g => (g.scoreOf(0).toDouble(), 'pts'),
  };

  // MARK: Textes

  String get _resultLine => switch (_g) {
    final LadderGame l => '${l.total} points, ${l.successes} sur ${l.count} finis.',
    final CheckoutDrill c => '${c.successes} sortie${c.successes > 1 ? 's' : ''} sur ${c.attempts}.',
    final JdcGame j => '${j.total} points, ${j.shanghais} Shanghai.',
    final Darts99Game d => '${d.total} points sur le ${_sector(d.sector)}.',
    final RoundTheWorldGame r => '${r.total} points sur le tour du monde.',
    final VolleyGame v => '${v.total} points en ${v.done} volées.',
    final CricketCountUpGame c => '${c.total} marques en ${c.volleys} volées.',
    _ => '',
  };

  List<CelebrationStat> get _endStats => switch (_g) {
    final LadderGame l => [
      CelebrationStat('Points', '${l.total}'),
      CelebrationStat('Réussite', '${l.rate} %'),
      CelebrationStat('Record', '${_record ?? '-'}'),
    ],
    final CheckoutDrill c => [
      CelebrationStat('Réussies', '${c.successes}/${c.attempts}'),
      CelebrationStat('Meilleure série', '${c.bestStreak}'),
      CelebrationStat(
        'Fléchettes moy.',
        c.dartsToFinish.isEmpty ? '-' : _fr(c.dartsToFinish.reduce((a, b) => a + b) / c.dartsToFinish.length),
      ),
    ],
    final JdcGame j => [
      CelebrationStat('Total', '${j.total}'),
      CelebrationStat('Shanghai', '${j.shanghais}'),
      CelebrationStat('Doubles', '${j.doubles}/21'),
    ],
    final Darts99Game d => [
      CelebrationStat('Total', '${d.total}'),
      CelebrationStat('Moyenne', _fr(d.average)),
      CelebrationStat('Triples', '${d.counts[2]}'),
    ],
    final RoundTheWorldGame r => [
      CelebrationStat('Points', '${r.total}'),
      CelebrationStat('Numéros touchés', '${r.points.where((p) => p > 0).length}/21'),
    ],
    final VolleyGame v => [
      CelebrationStat('Total', '${v.total}'),
      CelebrationStat('Moyenne', _fr(v.average)),
      CelebrationStat('Meilleure volée', '${v.best}'),
    ],
    final CricketCountUpGame c => [
      CelebrationStat('Marques', '${c.total}'),
      CelebrationStat('Par volée', _fr(c.average)),
    ],
    _ => const [],
  };

  static String _sector(int s) => s == 25 ? 'bull' : '$s';

  String get _headerLabel => switch (_g) {
    final LadderGame l => '${_cfg.title} · ${l.total} pts',
    final CheckoutDrill c => '${_mode == GameMode.nineDarts ? '9 Darts' : _cfg.title} · ${c.attempt} sur ${c.attempts}',
    final Darts99Game d => '99 fléchettes · ${_sector(d.sector)}',
    final RoundTheWorldGame r => 'Tour du monde · ${const ['simple', 'double', 'triple'][r.multiplier - 1]}',
    final VolleyGame v => 'Count Up · ${v.volleys} volées',
    _ => _cfg.title,
  };

  // MARK: Fléchettes

  bool _counts(int i, DartThrow d) => switch (_g) {
    final JdcGame j => j.dartCounts(i, d),
    final Darts99Game g => d.sector == g.sector,
    final RoundTheWorldGame r =>
      r.awaitingNextPlayer ? d.sector == RoundTheWorldGame.sectors[r.points.length - 1] : r.counts(d),
    final CricketCountUpGame _ => CricketCountUpGame.marksOf(d) > 0,
    _ => !d.isMiss,
  };

  List<SlotData> get _slots {
    final turn = _g.currentTurn;
    final cricket = _g is CricketCountUpGame;
    return [
      for (var i = 0; i < 3; i++)
        if (i < turn.length)
          _counts(i, turn[i])
              ? SlotData(SlotState.hit, label: turn[i].label, value: cricket ? turn[i].multiplier : turn[i].score)
              : SlotData(SlotState.miss, label: turn[i].isMiss ? null : turn[i].label, value: 0)
        else if (i == turn.length && !_g.awaitingNextPlayer && !_g.isFinished)
          const SlotData(SlotState.current)
        else
          const SlotData(SlotState.empty),
    ];
  }

  // MARK: Écran

  @override
  Widget build(BuildContext context) {
    final g = _g;
    return Scaffold(
      backgroundColor: Td.beton,
      body: Stack(
        children: [
          Stage(
            child: Padding(
              padding: const EdgeInsets.all(Td.s3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 236, child: _left()),
                  const SizedBox(width: Td.s3),
                  Expanded(child: _board()),
                  const SizedBox(width: Td.s3),
                  SizedBox(width: 300, child: _right()),
                ],
              ),
            ),
          ),
          if (_showEnd && g.isFinished)
            Positioned.fill(
              child: Celebration(
                kind: CelebrationKind.win,
                winner: _name,
                tag: _newRecord ? 'NOUVEAU RECORD' : 'FINI',
                copy: '$_resultLine${_newRecord ? ' Nouveau record.' : ' On remet ça ?'}',
                stats: _endStats,
                onAgain: _again,
                homeLabel: 'Terminer',
                onHome: () => Navigator.of(context).pop(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _left() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: Td.s2,
    children: [
      Row(
        spacing: Td.s2,
        children: [
          const StopGameButton(),
          Expanded(
            child: Text(
              _headerLabel,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TdText.inter(15, 20, 400, Td.ink2),
            ),
          ),
        ],
      ),
      PlayerCard(
        player: PlayerSummary(
          _name,
          status: PlayerStatus.active,
          detail: _record == null ? 'Premier essai' : 'Record $_record',
        ),
      ),
      ..._progress(),
      const Spacer(),
      TdButton(
        label: 'Corriger',
        icon: LucideIcons.pencil,
        variant: TdButtonVariant.secondary,
        height: Td.ciblePi,
        onPressed: _correct,
      ),
      TdButton(
        label: 'Hors cible',
        icon: LucideIcons.target,
        variant: TdButtonVariant.secondary,
        height: Td.ciblePi,
        onPressed: _outOfBoard,
      ),
    ],
  );

  /// Progression propre au jeu, sous la carte joueur.
  List<Widget> _progress() => switch (_g) {
    final LadderGame l => [
      _glass(
        _grid(
          cols: l.count > 20 ? 8 : 5,
          height: l.count > 20 ? 20 : 30,
          cells: [
            for (var i = 0; i < l.count; i++)
              _cell(
                '${l.from + i}',
                i < l.results.length
                    ? (l.results[i] >= 3
                          ? _Cell.top
                          : l.results[i] > 0
                          ? _Cell.ok
                          : _Cell.miss)
                    : i == l.results.length
                    ? _Cell.now
                    : _Cell.todo,
                small: l.count > 20,
              ),
          ],
        ),
      ),
      if (l.count > 20) _legend(const [('3 pts', Td.sunset), ('2 pts', Td.ink), ('Raté', Td.ink3)]),
    ],
    final CheckoutDrill c => [
      _glass(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Td.s2,
          children: [
            Text('Tentatives', style: TdText.inter(12, 16, 600, Td.ink2)),
            _grid(
              cols: 5,
              height: 26,
              cells: [
                for (var i = 0; i < c.attempts; i++)
                  _cell(
                    _mode == GameMode.randomCheckout ? '${c.targets[i]}' : '${i + 1}',
                    i < c.results.length
                        ? (c.results[i] ? _Cell.top : _Cell.miss)
                        : i == c.results.length
                        ? _Cell.now
                        : _Cell.todo,
                  ),
              ],
            ),
          ],
        ),
      ),
      Row(
        spacing: Td.s2,
        children: [
          Expanded(
            child: KpiTile(label: 'Réussite %', value: '${c.rate}'),
          ),
          Expanded(
            child: KpiTile(label: 'De suite', value: '${c.streak}'),
          ),
        ],
      ),
    ],
    final JdcGame j => [
      for (final (n, t, d) in [
        (1, 'Shanghai 10 à 15', 'Simple, double, triple'),
        (2, 'Un double par numéro', 'De 1 au bull, 50 pts'),
        (3, 'Shanghai 15 à 20', 'Le final'),
      ])
        _phaseRow(
          n,
          t,
          n == j.phase ? 'En cours · ${j.target == 25 ? 'bull' : j.target}' : d,
          n == j.phase,
          n < j.phase,
        ),
    ],
    final Darts99Game d => [
      _glass(
        Row(
          children: [
            for (final (k, n) in [('Simples', d.counts[0]), ('Doubles', d.counts[1]), ('Triples', d.counts[2])])
              Expanded(
                child: Column(
                  children: [
                    Text('$n', style: TdText.rounded(28, 900, Td.ink, height: 32)),
                    Text(k, style: TdText.inter(12, 16, 400, Td.ink2)),
                  ],
                ),
              ),
          ],
        ),
      ),
      _glass(
        _bars([for (final s in d.scores.reversed.take(8).toList().reversed) s], d.sector == 25 ? 150 : d.sector * 9, 8),
      ),
    ],
    final RoundTheWorldGame r => [
      _glass(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Td.s2,
          children: [
            Text('Points par numéro', style: TdText.inter(12, 16, 600, Td.ink2)),
            _grid(
              cols: 7,
              height: 34,
              cells: [
                for (var i = 0; i < RoundTheWorldGame.sectors.length; i++)
                  _cell(
                    i < r.points.length ? '${r.points[i]}' : (i == r.points.length ? '${r.current}' : ''),
                    i < r.points.length
                        ? (r.points[i] > 0 ? _Cell.ok : _Cell.miss)
                        : i == r.points.length
                        ? _Cell.now
                        : _Cell.todo,
                    top: RoundTheWorldGame.sectors[i] == 25 ? 'B' : '${RoundTheWorldGame.sectors[i]}',
                  ),
              ],
            ),
          ],
        ),
      ),
    ],
    final VolleyGame v => [_glass(_volleyRows(v))],
    final CricketCountUpGame c => [
      _glass(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Td.s1,
          children: [
            Text('Marques par numéro', style: TdText.inter(12, 16, 600, Td.ink2)),
            for (var i = 0; i < CricketGame.standard.length; i++)
              SizedBox(
                height: 24,
                child: Row(
                  children: [
                    SizedBox(
                      width: 40,
                      child: Text(
                        CricketGame.standard[i] == 25 ? 'Bull' : '${CricketGame.standard[i]}',
                        style: TdText.rounded(15, 900, Td.ink),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        c.marks[i] == 0 ? '·' : '|' * c.marks[i].clamp(0, 15),
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: TdText.inter(13, 18, 700, Td.sunset).copyWith(letterSpacing: 2),
                      ),
                    ),
                    Text('${c.marks[i]}', style: TdText.rounded(14, 800, Td.ink)),
                  ],
                ),
              ),
          ],
        ),
      ),
    ],
    _ => const [],
  };

  Widget _volleyRows(VolleyGame v) {
    final cur = v.awaitingNextPlayer ? -1 : v.done;
    return Column(
      spacing: Td.s1,
      children: [
        for (var i = 0; i < v.volleys; i++)
          SizedBox(
            height: 16,
            child: Row(
              spacing: 6,
              children: [
                SizedBox(width: 18, child: Text('${i + 1}', style: TdText.inter(12, 16, 400, Td.ink3))),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      height: 8,
                      color: Td.verreMoyen,
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: ((i < v.scores.length ? v.scores[i] : (i == cur ? v.current : 0)) / 180).clamp(
                          0.0,
                          1.0,
                        ),
                        heightFactor: 1,
                        child: ColoredBox(color: i == cur ? Td.ciel : Td.sunset),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 32,
                  child: Text(
                    i < v.scores.length ? '${v.scores[i]}' : (i == cur ? '${v.current}' : ''),
                    textAlign: TextAlign.right,
                    style: TdText.rounded(12, 800, Td.ink),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _phaseRow(int n, String title, String desc, bool on, bool done) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: Td.s2),
    decoration: BoxDecoration(
      color: Td.verreLeger,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: on ? Td.fluo : Td.bord),
      boxShadow: on ? const [BoxShadow(color: Color(0x66FFE14D), blurRadius: 20, blurStyle: BlurStyle.outer)] : null,
    ),
    child: Row(
      spacing: 10,
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: done ? Td.sunset : Td.asphalteHaut, borderRadius: BorderRadius.circular(10)),
          child: done
              ? const Icon(LucideIcons.check, size: 18, color: Td.onAccent)
              : Text('$n', style: TdText.rounded(17, 900, Td.ink)),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TdText.inter(15, 20, 600, Td.ink)),
              Text(desc, maxLines: 1, overflow: TextOverflow.ellipsis, style: TdText.inter(12, 16, 400, Td.ink2)),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _glass(Widget child) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Td.verreLeger,
      borderRadius: BorderRadius.circular(Td.rLg),
      border: Border.all(color: Td.verreBord),
    ),
    child: child,
  );

  Widget _legend(List<(String, Color)> items) => Row(
    spacing: Td.s3,
    children: [
      for (final (l, c) in items)
        Row(
          spacing: Td.s1,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)),
            ),
            Text(l, style: TdText.inter(12, 16, 400, Td.ink2)),
          ],
        ),
    ],
  );

  Widget _grid({required int cols, required double height, required List<Widget> cells}) => Column(
    spacing: 3,
    children: [
      for (var r = 0; r < (cells.length / cols).ceil(); r++)
        SizedBox(
          height: height,
          child: Row(
            spacing: 3,
            children: [
              for (var c = 0; c < cols; c++)
                Expanded(child: r * cols + c < cells.length ? cells[r * cols + c] : const SizedBox.shrink()),
            ],
          ),
        ),
    ],
  );

  Widget _cell(String text, _Cell state, {bool small = false, String? top}) {
    final (bg, fg) = switch (state) {
      _Cell.top => (Td.sunsetFond, Td.sunset),
      _Cell.ok => (Td.asphalteHaut, Td.ink),
      _Cell.miss => (Td.verreLeger, Td.ink3),
      _Cell.now => (Td.infoFond, Td.ink),
      _Cell.todo => (Td.verreLeger, Td.desactiveInk),
    };
    final label = Text(
      text,
      maxLines: 1,
      style: TdText.rounded(
        small ? 10 : 13,
        800,
        fg,
      ).copyWith(decoration: state == _Cell.miss ? TextDecoration.lineThrough : null),
    );
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(small ? 5 : 8),
        border: state == _Cell.now ? Border.all(color: Td.ciel, width: 1.5) : null,
      ),
      child: top == null
          ? label
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(top, style: TdText.inter(10, 12, 400, fg.withValues(alpha: 0.75))),
                label,
              ],
            ),
    );
  }

  /// Barres verticales des dernières volées.
  Widget _bars(List<int> values, int max, int slots) => SizedBox(
    height: 60,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      spacing: 6,
      children: [
        for (var i = 0; i < slots; i++)
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              spacing: 2,
              children: [
                Text(i < values.length ? '${values[i]}' : '', style: TdText.inter(11, 13, 400, Td.ink2)),
                Container(
                  height: i < values.length ? 4 + 38 * (values[i] / (max == 0 ? 1 : max)).clamp(0.0, 1.0) : 4,
                  decoration: BoxDecoration(
                    color: i < values.length ? (i == values.length - 1 ? Td.ciel : Td.sunset) : Td.verreMoyen,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  // MARK: Plateau

  DartThrow? get _aimed => switch (_g) {
    final LadderGame l => l.hint?.first,
    final CheckoutDrill c => c.hint?.first,
    final JdcGame j when j.phase == 2 => j.target == 25 ? null : DartThrow(j.target, 2),
    final Darts99Game d => d.sector == 25 ? null : DartThrow(d.sector, 3),
    final RoundTheWorldGame r => r.multiplier == 1 || r.target == 25 ? null : DartThrow(r.target, r.multiplier),
    _ => null,
  };

  int? get _aimSector => switch (_g) {
    final JdcGame j => j.phase == 2 && j.target != 25 ? null : j.target,
    final Darts99Game d => d.sector == 25 ? 25 : null,
    final RoundTheWorldGame r => r.multiplier == 1 || r.target == 25 ? r.target : null,
    _ => null,
  };

  Widget _board() {
    final d = _tagDart;
    final heat = _g is CricketCountUpGame ? CricketGame.standard.toSet() : const <int>{};
    return Center(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Dartboard(
            hits: _hits,
            aimed: _aimed,
            aimSector: _aimSector,
            heat: heat,
            dim: heat.isEmpty && (_aimed != null || _aimSector != null),
            onTapBoard: _onBoardTap,
          ),
          if (d != null)
            Positioned(
              left: -40,
              right: -40,
              top: d.isMiss ? null : 440 * 0.36 - 60,
              bottom: d.isMiss ? 8 : null,
              child: IgnorePointer(
                child: Center(
                  child: HitTag.forDart(d, key: ValueKey(_tagKey), fontSize: d.isMiss ? 48 : 72),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // MARK: Panneau de droite

  Widget _right() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    spacing: Td.s2,
    children: [
      ..._panel(),
      DartSlots(slots: _slots),
      TdButton(
        label: _g.isFinished ? 'Terminer' : _nextLabel,
        icon: LucideIcons.arrowRight,
        variant: _g.awaitingNextPlayer || _g.isFinished ? TdButtonVariant.primary : TdButtonVariant.secondary,
        height: Td.ciblePi,
        onPressed: _nextVolley,
      ),
    ],
  );

  String get _nextLabel {
    final g = _g;
    if (g is RoundTheWorldGame) {
      final i = g.points.length + (g.awaitingNextPlayer ? 0 : 1);
      if (i < RoundTheWorldGame.sectors.length) {
        final n = RoundTheWorldGame.sectors[i];
        return 'Passer au ${n == 25 ? 'bull' : n}';
      }
    }
    return 'Volée suivante';
  }

  List<Widget> _panel() {
    final g = _g;
    switch (g) {
      case final LadderGame l:
        final route = l.hint;
        final stake = l.pointsFor(l.dartsUsed + 1);
        return [
          ScoreDisplay(
            value: l.remaining,
            size: 88,
            state: route != null ? ScoreState.out : ScoreState.normal,
            label: 'Finis le ${l.target}',
            sub:
                'Fléchette ${(l.dartsUsed + 1).clamp(1, l.dartsPer)} sur ${l.dartsPer} · $stake pt${stake > 1 ? 's' : ''} en jeu',
          ),
          if (route != null)
            CheckoutHint(route: [for (final d in route) d.label])
          else
            const TdBanner(text: 'Pas de sortie possible avec ces fléchettes. Prépare la suivante.', alert: true),
        ];
      case final CheckoutDrill c:
        final route = c.hint;
        final last = c.lastResult;
        return [
          ScoreDisplay(
            value: c.remaining,
            size: 88,
            state: route != null ? ScoreState.out : ScoreState.normal,
            label: switch (_mode) {
              GameMode.randomCheckout => 'Finis le ${c.target}',
              GameMode.ton70 => 'Reste sur 170',
              _ => 'Reste, départ ${c.target}',
            },
            sub: _mode == GameMode.randomCheckout
                ? 'Volée ${c.volley.clamp(1, 3)} sur 3 · tentative ${c.attempt}'
                : 'Tentative ${c.attempt} · ${c.successes} réussie${c.successes > 1 ? 's' : ''}',
          ),
          if (route != null) CheckoutHint(route: [for (final d in route) d.label]),
          _pips(c),
          if (last != null && c.dartsUsed == 0 && !c.isFinished)
            TdBanner(text: last ? 'Réussi. On repart sur ${c.target}.' : 'Raté. Retour à ${c.target}.', error: !last),
        ];
      case final JdcGame j:
        return [
          ScoreDisplay(
            value: j.total,
            size: 88,
            label: '$_name, ton total',
            sub: 'Manche ${j.step + 1} sur ${JdcGame.steps} · cible ${j.target == 25 ? 'bull' : j.target}',
          ),
          if (j.phase == 2)
            const TdBanner(text: 'Une fléchette par double. 50 points le double.', error: false)
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: Td.s4, vertical: Td.s3),
              decoration: BoxDecoration(
                gradient: Td.goldenHour,
                borderRadius: BorderRadius.circular(Td.rLg),
                boxShadow: const [BoxShadow(color: Color(0x80FF4D8D), blurRadius: 40)],
              ),
              child: Row(
                spacing: Td.s3,
                children: [
                  const Icon(LucideIcons.flame, size: 24, color: Td.onAccent),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Shanghai sur le ${j.target}', style: TdText.inter(17, 22, 700, Td.onAccent)),
                        Text('Simple, double, triple. Bonus +100.', style: TdText.inter(13, 18, 400, Td.onAccent)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ];
      case final Darts99Game d:
        return [
          ScoreDisplay(
            value: d.total,
            size: 88,
            label: '$_name, ton total',
            sub: 'Volée ${d.volley} sur ${d.volleys} · cible ${_sector(d.sector)}',
          ),
          Row(
            spacing: Td.s2,
            children: [
              Expanded(
                child: KpiTile(label: 'Moyenne', value: _fr(d.average)),
              ),
              Expanded(
                child: KpiTile(label: 'Touches', value: '${d.hits}', unit: 'sur ${d.thrown}'),
              ),
            ],
          ),
        ];
      case final RoundTheWorldGame r:
        final next = r.points.length + 1 < RoundTheWorldGame.sectors.length
            ? RoundTheWorldGame.sectors[r.points.length + 1]
            : null;
        return [
          ScoreDisplay(
            value: r.target,
            text: r.target == 25 ? 'Bull' : null,
            size: 88,
            label: '$_name, vise le',
            sub: '${r.total} points · numéro ${r.points.length + (r.awaitingNextPlayer ? 0 : 1)} sur 21',
          ),
          TdBanner(
            text: next == null
                ? 'Dernière volée, sur le bull.'
                : 'Touché ou pas, tu passes au ${next == 25 ? 'bull' : next} après cette volée. Pas comme l’Around the clock.',
            error: false,
          ),
        ];
      case final VolleyGame v:
        final rec = _record;
        return [
          ScoreDisplay(
            value: v.total,
            size: 88,
            label: '$_name, ton total',
            sub: 'Volée ${(v.done + (v.awaitingNextPlayer ? 0 : 1)).clamp(1, v.volleys)} sur ${v.volleys}',
          ),
          Row(
            spacing: Td.s2,
            children: [
              Expanded(
                child: KpiTile(label: 'Moyenne', value: _fr(v.average)),
              ),
              Expanded(
                child: rec == null
                    ? KpiTile(label: 'Meilleure volée', value: '${v.best}', unit: 'pts')
                    : KpiTile(label: 'Manque au record', value: '${(rec - v.total).clamp(0, 9999)}', unit: 'pts'),
              ),
            ],
          ),
        ];
      case final CricketCountUpGame c:
        return [
          ScoreDisplay(
            value: c.total,
            size: 88,
            label: '$_name, tes marques',
            sub: 'Volée ${c.volley} sur ${c.volleys} · 15 à 20 et bull',
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 6,
            children: [
              Text('Marques par volée', style: TdText.inter(13, 18, 600, Td.ink2)),
              _bars(c.perVolley, 9, c.volleys),
            ],
          ),
        ];
      default:
        return const [];
    }
  }

  /// 9 pastilles : fléchettes utilisées sur la tentative.
  Widget _pips(CheckoutDrill c) => Row(
    spacing: 6,
    children: [
      for (var i = 0; i < c.maxDarts; i++)
        Expanded(
          child: Container(
            height: 14,
            decoration: BoxDecoration(
              color: i < c.dartsUsed ? Td.sunset : (i == c.dartsUsed ? Td.infoFond : Td.verreMoyen),
              borderRadius: BorderRadius.circular(7),
              border: i == c.dartsUsed ? Border.all(color: Td.ciel, width: 1.5) : null,
            ),
          ),
        ),
    ],
  );
}

enum _Cell { top, ok, miss, now, todo }
