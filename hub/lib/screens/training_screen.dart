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
import '../widgets/logo.dart';
import '../widgets/player_card.dart';
import '../widgets/stage.dart';
import '../widgets/td_button.dart';

/// Record d'entraînement dans l'historique : réussites sur une série ([target], [darts]),
/// ou meilleure volée libre quand [target] est null. Null si jamais joué.
int? practiceRecord(String name, {TrainingTarget? target, int darts = 15}) {
  final id = HistoryStore.playerId(name);
  int? best;
  for (final m in HistoryStore.instance.all()) {
    if (m['kind'] != 'training') continue;
    if (target == null ? m['drill'] != 'volleys' : (m['target'] != target.key || m['length'] != darts)) continue;
    for (final p in m['players'] as List) {
      final pm = p as Map;
      if (pm['id'] != id) continue;
      final h = ((target == null ? pm['best'] : pm['score']) as num?)?.toInt();
      if (h != null && (best == null || h > best)) best = h;
    }
  }
  return best;
}

/// Entraînement en solo (planche Entraînement), par volées de 3 :
/// série sur une cible ([GameConfig.training]) ou volées libres où l'on compte les points ([GameConfig.freeVolleys]).
/// Toucher le plateau lance aussi une fléchette à cet endroit.
class TrainingScreen extends StatefulWidget {
  const TrainingScreen({super.key, required this.config});

  final GameConfig config;

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  late TurnGame _g = _newGame();
  final List<BoardHit> _hits = [];

  /// Toutes les fléchettes de la série, avec leur position (carte de la cible dans les stats).
  final List<Map<String, Object?>> _throws = [];
  DartThrow? _tagDart;
  int _tagKey = 0;
  Timer? _tagTimer;
  Timer? _endTimer;
  bool _showEnd = false;
  bool _saved = false;

  /// Record avant cette série : réussites (cible) ou meilleure volée (volées libres), null si aucun.
  int? _record;

  GameConfig get _cfg => widget.config;
  TrainingTarget get _target => _cfg.training!;
  bool get _volleys => _cfg.training == null;
  String get _name => _cfg.players.isEmpty ? AppState.owner : _cfg.players.first;

  TurnGame _newGame() => _volleys
      ? VolleyGame(_name, volleys: _cfg.freeVolleys ?? 10)
      : TrainingGame(_name, target: _cfg.training!, darts: _cfg.trainingDarts);

  /// Valeur qui fait un record : réussites de la série, ou meilleure volée.
  int get _score => switch (_g) {
    final VolleyGame v => v.best,
    final TrainingGame t => t.hits,
    _ => 0,
  };

  @override
  void initState() {
    super.initState();
    AppState.lastGame = widget.config;
    _record = _bestSoFar();
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

  int? _bestSoFar() => practiceRecord(_name, target: _cfg.training, darts: _cfg.trainingDarts);

  /// Fin d'entraînement : série finie, ou volées sans fin arrêtées après au moins une volée.
  bool get _over => _g.isFinished || (_g is VolleyGame && (_g as VolleyGame).volleys == 0 && _stopped);
  bool _stopped = false;

  bool get _newRecord => _over && _score > 0 && (_record == null || _score > _record!);

  void _camDart(DartThrow d, Offset? pos) {
    if (mounted) _throw(d, pos ?? boardPositionFor(d));
  }

  /// Fléchettes retirées : volée suivante, une fois les 3 lancées.
  void _camTakeout() {
    if (mounted && _g.awaitingNextPlayer && !_g.isFinished) _nextVolley();
  }

  void _throw(DartThrow d, Offset pos) {
    if (_g.awaitingNextPlayer || _over) return;
    setState(() {
      _g.throwDart(d);
      _hits.add(BoardHit(d, pos, _hits.length + 1));
      _throws.add({'d': d.label, 'x': (pos.dx * 10).round() / 10, 'y': (pos.dy * 10).round() / 10});
      _tagDart = d;
      _tagKey++;
    });
    _tagTimer?.cancel();
    _tagTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _tagDart = null);
    });
    if (_g.isFinished) {
      AppState.lastResult = _result;
      _endTimer?.cancel();
      _endTimer = Timer(const Duration(milliseconds: 1400), () {
        if (mounted) setState(() => _showEnd = true);
      });
    }
  }

  void _onBoardTap(Offset p) => _throw(dartAt(p), p);

  /// Phrase de fin : "11 sur 15 au T20." ou "Moyenne 54,3, meilleure volée 100.".
  String get _result => switch (_g) {
    final TrainingGame t => '${t.hits} sur ${t.darts} au ${_target.label}.',
    final VolleyGame v => 'Moyenne ${_fr(v.average)}, meilleure volée ${v.best}.',
    _ => '',
  };

  static String _fr(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

  /// Volées sans fin : "Terminer" clôt la volée en cours et montre le bilan.
  void _finishEndless() {
    final v = _g as VolleyGame;
    if (v.currentTurn.isNotEmpty) v.nextPlayer();
    if (v.done == 0) {
      Navigator.of(context).pop();
      return;
    }
    AppState.lastResult = _result;
    setState(() {
      _stopped = true;
      _hits.clear();
      _tagDart = null;
      _showEnd = true;
    });
  }

  void _nextVolley() {
    if (_over) {
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
      _stopped = false;
      _record = _bestSoFar();
      _g = _newGame();
      _throws.clear();
      _hits.clear();
      _tagDart = null;
      _showEnd = false;
    });
  }

  /// Enregistre l'entraînement fini (une fois, en quittant ou avant de relancer).
  void _save() {
    if (!_over || _saved) return;
    _saved = true;
    final record = _record;
    if (record == null || _score > record) _record = _score;
    final g = _g;
    if (g is VolleyGame) {
      HistoryStore.instance.add({
        'id': '${DateTime.now().millisecondsSinceEpoch}',
        'at': DateTime.now().toIso8601String(),
        'mode': 'Volées libres',
        'kind': 'training',
        'drill': 'volleys',
        'winner': null,
        'players': [
          {
            'id': HistoryStore.playerId(_name),
            'name': _name,
            'won': false,
            'darts': g.dartsThrown,
            'score': g.total,
            'value': double.parse(g.average.toStringAsFixed(1)),
            'valueLabel': 'moy.',
            'best': g.best,
            'volleys': g.done,
            'scores': List.of(g.scores),
            'max180': g.max180,
            'throws': List.of(_throws),
          },
        ],
      });
      return;
    }
    g as TrainingGame;
    HistoryStore.instance.add({
      'id': '${DateTime.now().millisecondsSinceEpoch}',
      'at': DateTime.now().toIso8601String(),
      'mode': 'Série ${_target.label}',
      'kind': 'training',
      'drill': 'target',
      'target': _target.key,
      'length': g.darts,
      'winner': null,
      'players': [
        {
          'id': HistoryStore.playerId(_name),
          'name': _name,
          'won': false,
          'darts': g.thrown,
          'score': g.hits,
          'value': g.hits.toDouble(),
          'valueLabel': 'sur ${g.darts}',
          'bestStreak': g.bestStreak,
          'throws': List.of(_throws),
        },
      ],
    });
  }

  List<SlotData> get _slots {
    final turn = _g.currentTurn;
    return [
      for (var i = 0; i < 3; i++)
        if (i < turn.length)
          _volleys
              ? (turn[i].isMiss
                    ? const SlotData(SlotState.miss, value: 0)
                    : SlotData(SlotState.hit, label: turn[i].label, value: turn[i].score))
              : _target.matches(turn[i])
              ? SlotData(SlotState.hit, label: turn[i].label, value: turn[i].score)
              : SlotData(SlotState.miss, label: turn[i].isMiss ? null : turn[i].label, value: 0)
        else if (i == turn.length && !_g.awaitingNextPlayer && !_over)
          const SlotData(SlotState.current)
        else
          const SlotData(SlotState.empty),
    ];
  }

  String get _endCopy {
    final rec = _newRecord ? ' Nouveau record.' : ' On remet ça ?';
    return switch (_g) {
      final TrainingGame t => '${t.hits} sur ${t.darts} au ${_target.label}.$rec',
      final VolleyGame v => '${v.done} volée${v.done > 1 ? 's' : ''}, ${v.total} points.$rec',
      _ => '',
    };
  }

  List<CelebrationStat> get _endStats => switch (_g) {
    final TrainingGame t => [
      CelebrationStat('Réussite', '${t.rate} %'),
      CelebrationStat('Meilleure suite', '${t.bestStreak}'),
    ],
    final VolleyGame v => [
      CelebrationStat('Moyenne', _fr(v.average)),
      CelebrationStat('Meilleure volée', '${v.best}'),
    ],
    _ => const [],
  };

  @override
  Widget build(BuildContext context) {
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
          if (_showEnd && _over)
            Positioned.fill(
              child: Celebration(
                kind: CelebrationKind.win,
                winner: _name,
                tag: _newRecord ? 'RECORD' : 'FINI',
                copy: _endCopy,
                stats: _endStats,
                onAgain: _again,
                onHome: () => Navigator.of(context).pop(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _left() {
    final best = _newRecord ? _score : _record;
    final g = _g;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Td.s3,
      children: [
        Row(
          children: [
            GestureDetector(
              onLongPress: () => Navigator.of(context).pop(),
              child: const Logo(variant: LogoVariant.icon, height: 44),
            ),
            const Spacer(),
            Text('Entraînement', style: TdText.inter(15, 20, 400, Td.ink2)),
          ],
        ),
        PlayerCard(
          player: PlayerSummary(
            _name,
            status: PlayerStatus.active,
            detail: _volleys ? 'Volées libres' : 'Série ${_target.label}',
          ),
        ),
        if (g is TrainingGame)
          KpiTile(label: 'Record sur ${_target.label}', value: best == null ? '-' : '$best', unit: 'sur ${g.darts}')
        else
          KpiTile(label: 'Record de volée', value: best == null ? '-' : '$best', unit: 'points'),
        const Spacer(),
        TdButton(
          label: 'Arrêter',
          icon: LucideIcons.x,
          variant: TdButtonVariant.secondary,
          height: Td.ciblePi,
          onPressed: () => StopGameButton.confirm(context),
        ),
      ],
    );
  }

  Widget _board() {
    final d = _tagDart;
    final aim = _volleys ? null : _target;
    final bull = aim?.sector == 25;
    return Center(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Dartboard(
            hits: _hits,
            aimed: aim == null || bull ? null : DartThrow(aim.sector, aim.multiplier),
            aimSector: bull ? 25 : null,
            dim: aim != null,
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

  Widget _bar(String label, String value, double fraction, String foot) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: Td.s2,
    children: [
      Row(
        children: [
          Text(label, style: TdText.inter(13, 18, 600, Td.ink2)),
          const Spacer(),
          Text(value, style: TdText.inter(13, 18, 600, Td.ink)),
        ],
      ),
      ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Container(
          height: 10,
          color: const Color(0x17FFFFFF),
          alignment: Alignment.centerLeft,
          child: AnimatedFractionallySizedBox(
            duration: Td.base,
            curve: Td.courbeSortie,
            widthFactor: fraction.clamp(0.0, 1.0),
            heightFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(color: Td.sunset, borderRadius: BorderRadius.circular(5)),
            ),
          ),
        ),
      ),
      Text(foot, style: TdText.inter(13, 18, 400, Td.ink3)),
    ],
  );

  Widget _right() {
    final g = _g;
    final endless = g is VolleyGame && g.volleys == 0;
    final children = switch (g) {
      final TrainingGame t => [
        ScoreDisplay(
          value: t.hits,
          text: '${t.hits}/${t.thrown}',
          label: '${_target.plural} réussis',
          sub: 'Série de ${t.darts} fléchettes, ${t.thrown} lancée${t.thrown > 1 ? 's' : ''}',
        ),
        _bar('Réussite', '${t.rate} %', t.rate / 100, 'Meilleure suite: ${t.bestStreak} d’affilée'),
      ],
      final VolleyGame v => [
        ScoreDisplay(
          value: v.current,
          label: 'Cette volée',
          sub: v.volleys == 0
              ? 'Volée ${v.done + (v.awaitingNextPlayer ? 0 : 1)}'
              : 'Volée ${(v.done + (v.awaitingNextPlayer ? 0 : 1)).clamp(1, v.volleys)} sur ${v.volleys}',
        ),
        _bar(
          'Moyenne',
          _fr(v.average),
          v.average / 180,
          'Meilleure volée: ${v.best} · 100+: ${v.ton + v.ton40 + v.max180} · 180: ${v.max180}',
        ),
      ],
      _ => <Widget>[],
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      spacing: Td.s2,
      children: [
        ...children,
        DartSlots(slots: _slots),
        if (endless)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Td.s2,
            children: [
              TdButton(
                label: 'Terminer',
                icon: LucideIcons.flag,
                variant: TdButtonVariant.secondary,
                height: Td.ciblePi,
                onPressed: _finishEndless,
              ),
              _nextButton(),
            ],
          )
        else
          _nextButton(),
      ],
    );
  }

  Widget _nextButton() => TdButton(
    label: _over ? 'Terminer' : 'Volée suivante',
    icon: LucideIcons.arrowRight,
    variant: _g.awaitingNextPlayer || _over ? TdButtonVariant.primary : TdButtonVariant.secondary,
    height: Td.ciblePi,
    onPressed: _nextVolley,
  );
}
