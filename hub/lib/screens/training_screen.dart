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

/// Série libre en solo (planche Entraînement) : une cible, un nombre de fléchettes, par volées de 3.
/// En attendant les caméras, toucher le plateau lance une fléchette à cet endroit.
class TrainingScreen extends StatefulWidget {
  const TrainingScreen({super.key, required this.config});

  final GameConfig config;

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  late TrainingGame _g = _newGame();
  final List<BoardHit> _hits = [];
  DartThrow? _tagDart;
  int _tagKey = 0;
  Timer? _tagTimer;
  Timer? _endTimer;
  bool _showEnd = false;
  bool _saved = false;

  /// Record avant cette série (même joueur, même cible, même longueur), null si aucun.
  int? _record;

  GameConfig get _cfg => widget.config;
  TrainingTarget get _target => _cfg.training!;
  String get _name => _cfg.players.isEmpty ? AppState.owner : _cfg.players.first;

  TrainingGame _newGame() => TrainingGame(_name, target: _cfg.training!, darts: _cfg.trainingDarts);

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

  /// Meilleur nombre de réussites dans l'historique pour cette série.
  int? _bestSoFar() {
    final id = HistoryStore.playerId(_name);
    int? best;
    for (final m in HistoryStore.instance.all()) {
      if (m['kind'] != 'training' || m['target'] != _target.key || m['length'] != _cfg.trainingDarts) continue;
      for (final p in m['players'] as List) {
        final pm = p as Map;
        if (pm['id'] != id) continue;
        final h = (pm['score'] as num?)?.toInt();
        if (h != null && (best == null || h > best)) best = h;
      }
    }
    return best;
  }

  bool get _newRecord => _g.isFinished && _g.hits > 0 && (_record == null || _g.hits > _record!);

  void _camDart(DartThrow d, Offset? pos) {
    if (mounted) _throw(d, pos ?? boardPositionFor(d));
  }

  /// Fléchettes retirées : volée suivante, une fois les 3 lancées.
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
    if (_g.isFinished) {
      AppState.lastResult = '${_g.hits} sur ${_g.darts} au ${_target.label}.';
      _endTimer?.cancel();
      _endTimer = Timer(const Duration(milliseconds: 1400), () {
        if (mounted) setState(() => _showEnd = true);
      });
    }
  }

  void _onBoardTap(Offset p) => _throw(dartAt(p), p);

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
      _record = _bestSoFar();
      _g = _newGame();
      _hits.clear();
      _tagDart = null;
      _showEnd = false;
    });
  }

  /// Enregistre la série finie (une fois, en quittant ou avant de relancer).
  void _save() {
    final g = _g;
    if (!g.isFinished || _saved) return;
    _saved = true;
    final record = _record;
    if (record == null || g.hits > record) _record = g.hits;
    HistoryStore.instance.add({
      'id': '${DateTime.now().millisecondsSinceEpoch}',
      'at': DateTime.now().toIso8601String(),
      'mode': 'Série ${_target.label}',
      'kind': 'training',
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
        },
      ],
    });
  }

  List<SlotData> get _slots {
    final turn = _g.currentTurn;
    return [
      for (var i = 0; i < 3; i++)
        if (i < turn.length)
          _target.matches(turn[i])
              ? SlotData(SlotState.hit, label: turn[i].label, value: turn[i].score)
              : SlotData(SlotState.miss, label: turn[i].isMiss ? null : turn[i].label, value: 0)
        else if (i == turn.length && !_g.awaitingNextPlayer && !_g.isFinished)
          const SlotData(SlotState.current)
        else
          const SlotData(SlotState.empty),
    ];
  }

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
                tag: _newRecord ? 'RECORD' : 'FINI',
                copy: _newRecord
                    ? '${g.hits} sur ${g.darts} au ${_target.label}. Nouveau record.'
                    : '${g.hits} sur ${g.darts} au ${_target.label}. On remet ça ?',
                stats: [
                  CelebrationStat('Réussite', '${g.rate} %'),
                  CelebrationStat('Meilleure suite', '${g.bestStreak}'),
                ],
                onAgain: _again,
                onHome: () => Navigator.of(context).pop(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _left() {
    final best = _newRecord ? _g.hits : _record;
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
          player: PlayerSummary(_name, status: PlayerStatus.active, detail: 'Série ${_target.label}'),
        ),
        KpiTile(label: 'Record sur ${_target.label}', value: best == null ? '-' : '$best', unit: 'sur ${_g.darts}'),
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
    final bull = _target.sector == 25;
    return Center(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Dartboard(
            hits: _hits,
            aimed: bull ? null : DartThrow(_target.sector, _target.multiplier),
            aimSector: bull ? 25 : null,
            dim: true,
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

  Widget _right() {
    final g = _g;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      spacing: Td.s2,
      children: [
        ScoreDisplay(
          value: g.hits,
          text: '${g.hits}/${g.thrown}',
          label: '${_target.plural} réussis',
          sub: 'Série de ${g.darts} fléchettes, ${g.thrown} lancée${g.thrown > 1 ? 's' : ''}',
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Td.s2,
          children: [
            Row(
              children: [
                Text('Réussite', style: TdText.inter(13, 18, 600, Td.ink2)),
                const Spacer(),
                Text('${g.rate} %', style: TdText.inter(13, 18, 600, Td.ink)),
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
                  widthFactor: g.rate / 100,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: Td.sunset, borderRadius: BorderRadius.circular(5)),
                  ),
                ),
              ),
            ),
            Text(
              'Meilleure suite: ${g.bestStreak} d’affilée',
              style: TdText.inter(13, 18, 400, Td.ink3),
            ),
          ],
        ),
        DartSlots(slots: _slots),
        TdButton(
          label: g.isFinished ? 'Terminer' : 'Volée suivante',
          icon: LucideIcons.arrowRight,
          variant: g.awaitingNextPlayer || g.isFinished ? TdButtonVariant.primary : TdButtonVariant.secondary,
          height: Td.ciblePi,
          onPressed: _nextVolley,
        ),
      ],
    );
  }
}
