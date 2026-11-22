import 'dart:async';
import 'dart:math' as math;

import 'package:darts_engine/darts_engine.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../cam/cam_link.dart';
import '../coach/coach_store.dart';
import '../game/paused_game.dart';
import '../game_config.dart';
import '../history/history_store.dart';
import '../system/sounds.dart';
import '../theme/tokens.dart';
import '../widgets/celebration.dart';
import '../widgets/controls.dart';
import '../widgets/dartboard.dart';
import '../widgets/game_widgets.dart';
import '../widgets/hit_tag.dart';
import '../widgets/player_card.dart';
import '../widgets/stage.dart';
import '../widgets/td_button.dart';
import '../widgets/volume_button.dart';
import 'correction_screen.dart';

/// Chrono d'une volée sous pression.
const _pressureSeconds = 20;

/// Coach adaptatif des check-out : carte des doubles, puis la séance du jour
/// (2 doubles faibles, sorties, pression). Chaque niveau se règle pour réussir 60 % du temps.
class CoachScreen extends StatefulWidget {
  const CoachScreen({super.key, required this.config, this.paused});

  final GameConfig config;

  /// Séance reprise après une pause.
  final PausedGame? paused;

  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends State<CoachScreen> {
  GameConfig get _cfg => widget.config;
  String get _name => _cfg.players.isEmpty ? AppState.owner : _cfg.players.first;
  String get _id => HistoryStore.playerId(_name);

  late CoachStore _store = CoachStore.forName(_name);
  late GameLog _log = GameLog(seed: widget.paused?.seed ?? _store.seedFor(_id), replayLog: widget.paused?.log);
  late List<CoachStep> _plan = coachPlan(_store.profile);
  late CoachSession _g = _newSession();

  bool _started = false;
  final List<BoardHit> _hits = [];
  DartThrow? _tagDart;
  int _tagKey = 0;
  Timer? _tagTimer;
  Timer? _endTimer;
  Timer? _clock;
  int _secondsLeft = _pressureSeconds;
  bool _showEnd = false;
  bool _saved = false;

  CoachSession _newSession() => CoachSession(_name, plan: _plan, levels: _store.profile.levels, seed: _log.seed);

  @override
  void initState() {
    super.initState();
    AppState.lastGame = widget.config;
    CamLink.instance
      ..debugGame = widget.config.label
      ..onDart = _camDart
      ..onTakeout = _camTakeout;
    if (widget.paused != null) {
      _started = true;
      _log.replay(_apply);
      PausedGame.clear();
    }
    _sync();
  }

  @override
  void dispose() {
    _tagTimer?.cancel();
    _endTimer?.cancel();
    _clock?.cancel();
    _save();
    if (CamLink.instance.onDart == _camDart) {
      CamLink.instance
        ..onDart = null
        ..onTakeout = null
        ..setPlaying(false);
    }
    super.dispose();
  }

  // MARK: Jeu

  void _start() {
    setState(() => _started = true);
    _sync();
  }

  void _apply(Map<String, Object?> e) {
    switch (e['t']) {
      case 'd':
        _throw(GameLog.dartOf(e), GameLog.offsetOf(e) ?? boardPositionFor(GameLog.dartOf(e)));
      case 'c':
        _applyCorrection(GameLog.correctionOf(e));
      case 'e':
        _nextVolley();
      case 'x':
        _timeUp();
    }
  }

  void _pause() {
    _log.pause(_cfg);
    Navigator.of(context).pop();
  }

  void _camDart(DartThrow d, Offset? pos, String? traceId) {
    if (!mounted || !_started) return;
    Sounds.dart(d);
    _throw(d, pos ?? boardPositionFor(d), traceId: traceId);
  }

  void _camTakeout() {
    if (mounted && _started && _g.awaitingNextPlayer && !_g.isFinished) _nextVolley();
  }

  void _throw(DartThrow d, Offset pos, {String? traceId}) {
    if (_g.awaitingNextPlayer || _g.isFinished) return;
    _log.add(GameLog.dart('d', d, x: pos.dx, y: pos.dy));
    setState(() {
      _g.throwAt(d, pos.dx, pos.dy);
      _hits.add(BoardHit(d, pos, _hits.length + 1, traceId: traceId));
      _tagDart = d;
      _tagKey++;
    });
    _tagTimer?.cancel();
    _tagTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _tagDart = null);
    });
    _afterDart();
  }

  void _afterDart() {
    if (_g.awaitingNextPlayer) _clock?.cancel();
    _sync();
    _scheduleEnd();
  }

  void _scheduleEnd() {
    _endTimer?.cancel();
    if (!_g.isFinished) {
      _showEnd = false;
      return;
    }
    AppState.lastResult = '$_name : coach, ${_g.scoreOf(0)} % dans la zone';
    _endTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted && _g.isFinished) setState(() => _showEnd = true);
    });
  }

  void _onBoardTap(Offset p) {
    if (!_started) return;
    CamLink.instance.debugTruth('manuelle', real: dartAt(p), position: p);
    Sounds.dart(dartAt(p));
    _throw(dartAt(p), p);
  }

  void _outOfBoard() {
    CamLink.instance.debugTruth('manuelle', real: const DartThrow.miss());
    Sounds.play('miss');
    _throw(const DartThrow.miss(), const Offset(38.7, 181.9));
  }

  Future<void> _correct() async {
    if (_showEnd || !_started) return;
    final c = await Navigator.of(context).push<Correction>(
      MaterialPageRoute(
        builder: (_) => CorrectionScreen(turn: _g.currentTurn, hits: List.of(_hits)),
      ),
    );
    if (c == null || !mounted) return;
    _applyCorrection(c);
  }

  void _applyCorrection(Correction c) {
    _log.add(GameLog.correction(c));
    final pos = c.position ?? boardPositionFor(c.dart);
    setState(() {
      _g.correctAt(c.index, c.dart, x: pos.dx, y: pos.dy);
      final kept = <BoardHit>[];
      for (var i = 0; i < _g.currentTurn.length; i++) {
        final d = _g.currentTurn[i];
        final old = i < _hits.length ? _hits[i] : null;
        kept.add(
          old != null && old.dart == d && i != c.index
              ? old
              : BoardHit(d, i == c.index ? pos : boardPositionFor(d), i + 1, traceId: old?.traceId),
        );
      }
      _hits
        ..clear()
        ..addAll(kept);
      _tagDart = null;
    });
    _afterDart();
  }

  void _nextVolley() {
    if (!_log.replaying) CamLink.instance.turnEnded();
    _log.add({'t': 'e'});
    if (_g.isFinished) {
      setState(() => _showEnd = true);
      return;
    }
    setState(() {
      _g.nextPlayer();
      _hits.clear();
      _tagDart = null;
    });
    _sync();
  }

  /// Chrono fini : le reste de la volée compte comme raté.
  void _timeUp() {
    if (_g.awaitingNextPlayer || _g.isFinished) return;
    _log.add({'t': 'x'});
    Sounds.play('miss');
    setState(() => _g.timeUp());
    _afterDart();
  }

  void _again() {
    _endTimer?.cancel();
    _save();
    setState(() {
      _saved = false;
      _store = CoachStore.forName(_name);
      _log = GameLog(seed: _store.seedFor(_id));
      _plan = coachPlan(_store.profile);
      _g = _newSession();
      _hits.clear();
      _tagDart = null;
      _showEnd = false;
      _started = false;
    });
    _sync();
  }

  /// Projecteur et caméras, et chrono de la pression. La lumière ne change qu'entre deux volées.
  void _sync() {
    final g = _g;
    final playing = _started && !g.isFinished;
    final aim = g.awaitingNextPlayer ? null : g.aim;
    final route = g.hint;
    if (!g.awaitingNextPlayer) {
      CamLink.instance.setGameInfo(
        'Coach',
        checkout: route == null || route.length < 2 ? null : [for (final d in route) d.label],
        coachCell: playing ? aim?.label : null,
        coachZone: g.step.kind == CoachStepKind.doubles ? g.zone : 1,
      );
    } else {
      CamLink.instance.setGameInfo('Coach', wait: true);
    }
    CamLink.instance.setPlaying(playing);
    final pressure = playing && g.step.kind == CoachStepKind.pressure && !g.awaitingNextPlayer;
    if (!pressure || _log.replaying) {
      _clock?.cancel();
      _clock = null;
      return;
    }
    if (g.currentTurn.isEmpty && _clock == null) {
      _secondsLeft = _pressureSeconds;
      _clock = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return t.cancel();
        setState(() => _secondsLeft--);
        if (_secondsLeft <= 0) {
          t.cancel();
          _clock = null;
          _timeUp();
        }
      });
    }
  }

  // MARK: Historique

  void _save() {
    if (_log.replaying || !_started) return;
    final g = _g;
    if (!g.isFinished || _saved) return;
    _saved = true;
    final doubles = g.doubleHits;
    int pctOf(int ok, int total) => total == 0 ? 0 : (ok * 100 / total).round();
    final zoneShots = g.shots.where((s) => g.plan[s.step].kind == CoachStepKind.doubles).toList();
    final co = g.checkouts.where((c) => c.ghost == null).toList();
    final pr = g.checkouts.where((c) => c.ghost != null).toList();
    final zonePct = pctOf(zoneShots.where((s) => s.ok).length, zoneShots.length);
    final darts = g.turnsOf(0).fold<int>(0, (n, t) => n + t.length);
    HistoryStore.instance.add({
      'id': '${DateTime.now().millisecondsSinceEpoch}',
      'at': DateTime.now().toIso8601String(),
      'mode': _cfg.title,
      'kind': GameMode.coach.name,
      'training': true,
      'option': 0,
      'winner': null,
      'players': [
        {
          'id': _id,
          'name': _name,
          'won': false,
          'darts': darts,
          'score': zonePct,
          'value': zonePct.toDouble(),
          'valueLabel': '% zone',
          'zonePct': zonePct,
          'doublePct': pctOf(doubles.ok, doubles.total),
          'checkoutOk': co.where((c) => c.ok == true).length,
          'checkoutTotal': co.length,
          'pressureOk': pr.where((c) => c.ok == true).length,
          'pressureTotal': pr.length,
          'plan': [for (final s in g.plan) s.toJson()],
          'shots': [for (final s in g.shots) s.toJson()],
          'checkouts': [for (final c in g.checkouts) c.toJson()],
          'levels': g.levels.toJson(),
        },
      ],
    });
  }

  // MARK: Textes

  static String _pct(int ok, int total) => total == 0 ? '-' : '${(ok * 100 / total).round()} %';

  String _zoneLabel(double z) => z >= 0.999 ? 'double entier' : 'zone ${(z * 100).round()} %';

  String _stepDesc(int i) {
    final s = _plan[i];
    final p = _store.profile;
    return switch (s.kind) {
      CoachStepKind.doubles =>
        '${s.count} volées · ${p.skills[s.target!.label]!.pct == null ? 'jamais tenté' : '${p.skills[s.target!.label]!.pct} %'} · ${_zoneLabel(zoneFraction(p.levels.zone(s.target!)))}',
      CoachStepKind.checkouts => () {
        final (lo, hi) = checkoutRanges[p.levels.checkout.floor().clamp(0, checkoutRanges.length - 1)];
        return '${s.count} sorties · $lo à $hi';
      }(),
      CoachStepKind.pressure =>
        '${s.count} manches · ${(3 - p.levels.pressure.floor()).clamp(1, 3)} volée(s) · ${_pressureSeconds}s',
    };
  }

  /// Écart moyen en mots : "6 mm à gauche · 3 mm haut".
  String? _biasText(DoubleSkill s) {
    if (s.placed < 3) return null;
    final o = _biasVector(s);
    final parts = <String>[
      if (o.dx.abs() >= 1) '${o.dx.abs().round()} mm ${o.dx < 0 ? 'à gauche' : 'à droite'}',
      if (o.dy.abs() >= 1) '${o.dy.abs().round()} mm ${o.dy < 0 ? 'haut' : 'bas'}',
    ];
    return parts.isEmpty ? 'Centré' : parts.join(' · ');
  }

  /// Écart moyen d'un double en x, y (mm, y vers le bas).
  Offset _biasVector(DoubleSkill s) {
    if (s.target.sector == 25) return Offset(s.tangential, -s.radial);
    final a = sectors.indexOf(s.target.sector) * 18 * math.pi / 180;
    final ur = Offset(math.sin(a), -math.cos(a)), ut = Offset(math.cos(a), math.sin(a));
    return ur * s.radial + ut * s.tangential;
  }

  Offset _mid(DartThrow d) {
    if (d.sector == 25) return Offset.zero;
    final a = sectors.indexOf(d.sector) * 18 * math.pi / 180;
    return Offset(doubleMidRadius * math.sin(a), -doubleMidRadius * math.cos(a));
  }

  // MARK: Écran

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
                  SizedBox(width: 300, child: _started ? _right() : _intro()),
                ],
              ),
            ),
          ),
          if (_showEnd && _g.isFinished) Positioned.fill(child: _end()),
        ],
      ),
    );
  }

  Widget _end() {
    final g = _g;
    final zoneShots = g.shots.where((s) => g.plan[s.step].kind == CoachStepKind.doubles).toList();
    final co = g.checkouts.where((c) => c.ghost == null).toList();
    final pr = g.checkouts.where((c) => c.ghost != null).toList();
    final d = g.doubleHits;
    return Celebration(
      kind: CelebrationKind.win,
      winner: _name,
      tag: 'SÉANCE FINIE',
      copy:
          'Zone ${_pct(zoneShots.where((s) => s.ok).length, zoneShots.length)} · doubles ${_pct(d.ok, d.total)} · sorties ${co.where((c) => c.ok == true).length}/${co.length} · pression ${pr.where((c) => c.ok == true).length}/${pr.length}.',
      stats: [
        CelebrationStat('Zone', _pct(zoneShots.where((s) => s.ok).length, zoneShots.length)),
        CelebrationStat('Doubles', _pct(d.ok, d.total)),
        CelebrationStat('Sorties', '${co.where((c) => c.ok == true).length}/${co.length}'),
        CelebrationStat('Pression', '${pr.where((c) => c.ok == true).length}/${pr.length}'),
      ],
      onAgain: _again,
      homeLabel: 'Terminer',
      onHome: () => Navigator.of(context).pop(),
    );
  }

  Widget _left() {
    final p = _store.profile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Td.s2,
      children: [
        Row(
          spacing: Td.s2,
          children: [
            if (_started)
              StopGameButton(onPause: _g.isFinished ? null : _pause)
            else
              TdIconButton(
                icon: LucideIcons.chevronLeft,
                label: 'Retour',
                onPressed: () => Navigator.of(context).pop(),
              ),
            const VolumeButton(),
            Expanded(
              child: Text(
                _store.todayCount == 0 ? 'Séance du jour' : 'Séance ${_store.todayCount + 1}',
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
            detail: p.attempts == 0 ? 'Premier essai' : 'Doubles ${_pct(p.hits, p.attempts)}',
          ),
        ),
        for (var i = 0; i < _plan.length; i++)
          _stepRow(
            i + 1,
            _plan[i].title,
            _started && i == _g.stepIndex && !_g.isFinished ? _stepNow(i) : _stepDone(i) ?? _stepDesc(i),
            _started && i == _g.stepIndex && !_g.isFinished,
            _started && (i < _g.stepIndex || _g.isFinished),
          ),
        const Spacer(),
        if (_started) ...[
          TdButton(
            label: 'Corriger',
            icon: LucideIcons.pencil,
            variant: TdButtonVariant.secondary,
            height: 56,
            onPressed: _correct,
          ),
          TdButton(
            label: 'Hors cible',
            icon: LucideIcons.target,
            variant: TdButtonVariant.secondary,
            height: 56,
            onPressed: _outOfBoard,
          ),
        ],
      ],
    );
  }

  String _stepNow(int i) {
    final g = _g;
    final s = _plan[i];
    final r = g.resultOf(i);
    return switch (s.kind) {
      CoachStepKind.doubles => 'Volée ${math.min(g.volleysInStep + 1, s.count)} sur ${s.count} · ${r.ok}/${r.total}',
      _ => '${math.min(g.volleysInStep + 1, s.count)} sur ${s.count} · ${r.ok} réussie${r.ok > 1 ? 's' : ''}',
    };
  }

  String? _stepDone(int i) {
    if (!_started || (i >= _g.stepIndex && !_g.isFinished)) return null;
    final r = _g.resultOf(i);
    return '${r.ok}/${r.total} · ${_pct(r.ok, r.total)}';
  }

  // MARK: Plateau

  Widget _board() {
    final g = _g;
    final p = _store.profile;
    final aim = _started && !g.isFinished ? g.aim : null;
    final d = _tagDart;
    return Center(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Dartboard(
            hits: _hits,
            aimed: aim,
            dim: aim != null,
            zone: _started && g.step.kind == CoachStepKind.doubles ? g.zone : 1,
            doubleRates: _started
                ? const {}
                : {
                    for (final s in p.skills.values)
                      if (s.pct != null) (s.target.sector == 25 ? 'BULL' : s.label): s.pct!,
                  },
            bias: _started
                ? const []
                : [
                    for (final s in p.skills.values)
                      if (s.placed >= 3) (_mid(s.target), _mid(s.target) + _biasVector(s) * 2),
                  ],
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

  // MARK: Avant la séance : carte des doubles

  Widget _intro() {
    final p = _store.profile;
    final weak = p.weakest.take(2).toList();
    final strong = p.acquired;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Td.s2,
      children: [
        Text('Carte des doubles', style: TdText.inter(13, 18, 600, Td.ink2)),
        _legend(const [('50 %+', Td.fluo), ('35 %', Td.sunset), ('20 %', Td.crepuscule), ('-20 %', Td.plateauRouge)]),
        for (final s in weak) _skillRow(s, 'À travailler'),
        _skillRow(strong, 'Acquis'),
        Row(
          spacing: Td.s2,
          children: [
            Expanded(
              child: KpiTile(label: 'Doubles', value: _pct(p.hits, p.attempts)),
            ),
            Expanded(
              child: KpiTile(
                label: 'Sorties',
                value: '${p.levels.checkout.floor().clamp(0, checkoutRanges.length - 1) + 1}/${checkoutRanges.length}',
              ),
            ),
          ],
        ),
        const Spacer(),
        TdButton(
          label: 'Commencer',
          icon: LucideIcons.play,
          variant: TdButtonVariant.primary,
          height: Td.ciblePi,
          onPressed: _start,
        ),
      ],
    );
  }

  Widget _skillRow(DoubleSkill s, String tag) {
    final bias = _biasText(s);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: Td.s2),
      decoration: BoxDecoration(
        color: Td.verreLeger,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Td.bord),
      ),
      child: Row(
        spacing: 10,
        children: [
          SizedBox(width: 52, child: Text(s.label, style: TdText.rounded(20, 900, Td.ink))),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$tag · ${s.pct == null ? 'jamais tenté' : '${s.pct} % sur ${s.attempts}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TdText.inter(13, 18, 600, Td.ink),
                ),
                if (bias != null)
                  Text(bias, maxLines: 1, overflow: TextOverflow.ellipsis, style: TdText.inter(12, 16, 400, Td.ink2)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // MARK: Pendant la séance

  Widget _right() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    spacing: Td.s2,
    children: [
      ..._panel(),
      DartSlots(slots: _slots),
      TdButton(
        label: _g.isFinished ? 'Terminer' : 'Volée suivante',
        icon: LucideIcons.arrowRight,
        variant: _g.awaitingNextPlayer || _g.isFinished ? TdButtonVariant.primary : TdButtonVariant.secondary,
        height: Td.ciblePi,
        onPressed: _nextVolley,
      ),
    ],
  );

  List<Widget> _panel() {
    final g = _g;
    final s = g.step;
    switch (s.kind) {
      case CoachStepKind.doubles:
        final t = s.target!;
        final skill = _store.profile.skills[t.label]!;
        final r = g.resultOf(g.stepIndex);
        final inCell = g.shots.where((x) => x.step == g.stepIndex && x.dart == x.aim).length;
        final bias = _biasText(skill);
        return [
          ScoreDisplay(
            value: 0,
            text: t.sector == 25 ? 'Bull' : t.label,
            size: 88,
            label: 'Vise',
            sub: 'Volée ${math.min(g.volleysInStep + 1, s.count)} sur ${s.count} · ${_zoneLabel(g.zone)}',
          ),
          Row(
            spacing: Td.s2,
            children: [
              Expanded(
                child: KpiTile(label: 'Dans la zone', value: '${r.ok}/${r.total}'),
              ),
              Expanded(
                child: KpiTile(label: 'Dans le double', value: '$inCell/${r.total}'),
              ),
            ],
          ),
          if (bias != null) TdBanner(text: 'Écart moyen : $bias', error: false),
        ];
      case CoachStepKind.checkouts:
        final c = g.current!;
        final route = g.hint;
        final r = g.resultOf(g.stepIndex);
        final last = g.checkouts.where((x) => x.step == g.stepIndex).lastOrNull;
        return [
          ScoreDisplay(
            value: g.remaining,
            size: 88,
            state: route != null ? ScoreState.out : ScoreState.normal,
            label: 'Finis le ${c.score}',
            sub:
                'Volée ${g.volley.clamp(1, g.maxDarts ~/ 3)} sur ${g.maxDarts ~/ 3} · sortie ${math.min(g.volleysInStep + 1, s.count)} sur ${s.count} · ${g.remainingRange.$1} à ${g.remainingRange.$2}',
          ),
          if (route != null) CheckoutHint(route: [for (final d in route) d.label]),
          _pips(g.dartsUsed, g.maxDarts),
          Row(
            spacing: Td.s2,
            children: [
              Expanded(
                child: KpiTile(label: 'Réussies', value: '${r.ok}/${r.total}'),
              ),
              Expanded(
                child: KpiTile(label: 'Niveau', value: '${g.levels.checkout.floor() + 1}/${checkoutRanges.length}'),
              ),
            ],
          ),
          if (last != null && g.dartsUsed == 0)
            TdBanner(text: last.ok == true ? 'Réussi : ${last.score}' : 'Raté : ${last.score}', error: last.ok != true),
        ];
      case CoachStepKind.pressure:
        final c = g.current!;
        final route = g.hint;
        final ghost = g.ghostRest;
        return [
          ScoreDisplay(
            value: g.remaining,
            size: 88,
            state: route != null ? ScoreState.out : ScoreState.normal,
            label: 'Finis le ${c.score}',
            sub:
                'Manche ${math.min(g.volleysInStep + 1, s.count)} sur ${s.count} · volée ${g.volley.clamp(1, c.ghost!)} sur ${c.ghost}',
          ),
          if (route != null) CheckoutHint(route: [for (final d in route) d.label]),
          Row(
            spacing: Td.s2,
            children: [
              Expanded(
                child: KpiTile(label: 'Fantôme', value: ghost == 0 ? 'Fini' : '$ghost'),
              ),
              Expanded(
                child: KpiTile(label: 'Chrono', value: g.awaitingNextPlayer ? '-' : '$_secondsLeft', unit: 's'),
              ),
            ],
          ),
          _chrono(),
        ];
    }
  }

  Widget _chrono() {
    final k = (_secondsLeft / _pressureSeconds).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: Container(
        height: 14,
        color: Td.verreMoyen,
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: _g.awaitingNextPlayer ? 0 : k,
          heightFactor: 1,
          child: ColoredBox(color: _secondsLeft <= 5 ? Td.erreur : Td.sunset),
        ),
      ),
    );
  }

  List<SlotData> get _slots {
    final turn = _g.currentTurn;
    final doubles = _g.step.kind == CoachStepKind.doubles;
    return [
      for (var i = 0; i < 3; i++)
        if (i < turn.length)
          (doubles ? turn[i] == _g.step.target : !turn[i].isMiss)
              ? SlotData(SlotState.hit, label: turn[i].label, value: turn[i].score)
              : const SlotData(SlotState.miss, value: 0)
        else if (i == turn.length && !_g.awaitingNextPlayer && !_g.isFinished)
          const SlotData(SlotState.current)
        else
          const SlotData(SlotState.empty),
    ];
  }

  Widget _pips(int used, int max) => Row(
    spacing: 6,
    children: [
      for (var i = 0; i < max; i++)
        Expanded(
          child: Container(
            height: 14,
            decoration: BoxDecoration(
              color: i < used ? Td.sunset : (i == used ? Td.infoFond : Td.verreMoyen),
              borderRadius: BorderRadius.circular(7),
              border: i == used ? Border.all(color: Td.ciel, width: 1.5) : null,
            ),
          ),
        ),
    ],
  );

  Widget _stepRow(int n, String title, String desc, bool on, bool done) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: done ? Td.sunset : Td.asphalteHaut, borderRadius: BorderRadius.circular(9)),
          child: done
              ? const Icon(LucideIcons.check, size: 16, color: Td.onAccent)
              : Text('$n', style: TdText.rounded(15, 900, Td.ink)),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TdText.inter(14, 18, 600, Td.ink)),
              Text(desc, maxLines: 1, overflow: TextOverflow.ellipsis, style: TdText.inter(11, 14, 400, Td.ink2)),
            ],
          ),
        ),
      ],
    ),
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
}
