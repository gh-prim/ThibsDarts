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
import '../stats/owner_stats.dart';
import '../system/sounds.dart';
import '../theme/tokens.dart';
import '../widgets/celebration.dart';
import '../widgets/controls.dart';
import '../widgets/dartboard.dart';
import '../widgets/game_widgets.dart';
import '../widgets/hit_tag.dart';
import '../widgets/stage.dart';
import '../widgets/td_button.dart';
import '../widgets/volume_button.dart';
import 'correction_screen.dart';
import '../widgets/cancel_dart.dart';

/// Doubles Pro : routine fixe sur tous les doubles (diagnostic, chaînes, aléatoire, échelle).
/// [GameConfig.option] : 0 la séance complète, 1 à 4 un seul bloc.
class DoublesProScreen extends StatefulWidget {
  const DoublesProScreen({super.key, required this.config, this.paused});

  final GameConfig config;

  /// Séance reprise après une pause.
  final PausedGame? paused;

  @override
  State<DoublesProScreen> createState() => _DoublesProScreenState();
}

/// Séances Doubles Pro d'un joueur, lues dans l'historique.
class DoublesProStore {
  DoublesProStore(String name) : id = HistoryStore.playerId(name), coach = CoachStore.forName(name);

  final String id;
  final CoachStore coach;

  late final List<StatEntry> sessions = coach.stats.entries.where((e) => e.kind == GameMode.doublesPro.name).toList()
    ..sort((a, b) => a.at.compareTo(b.at));

  /// Jours d'affilée avec une séance, jusqu'à aujourd'hui ou hier.
  int get streak => _streak(sessions.map((e) => e.at));

  /// Plus longue série de jours.
  int get bestStreak {
    final days = _days(sessions.map((e) => e.at)).toList()..sort();
    var best = 0, run = 0;
    DateTime? prev;
    for (final d in days) {
      run = prev != null && d.difference(prev).inDays == 1 ? run + 1 : 1;
      best = math.max(best, run);
      prev = d;
    }
    return best;
  }

  static Set<DateTime> _days(Iterable<DateTime> at) => {for (final a in at) DateTime(a.year, a.month, a.day)};

  static int _streak(Iterable<DateTime> at) {
    final days = _days(at);
    final now = DateTime.now();
    var d = DateTime(now.year, now.month, now.day);
    if (!days.contains(d)) d = d.subtract(const Duration(days: 1));
    var n = 0;
    while (days.contains(d)) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  /// Dernier résultat de chaque bloc ("9/15", "4,4 fl.", "27 %", "56").
  String? lastOf(DpBlock b) {
    for (final e in sessions.reversed) {
      final r = e.p['blocks'];
      if (r is Map && r[b.name] is String) return r[b.name] as String;
    }
    return null;
  }
}

class _DoublesProScreenState extends State<DoublesProScreen> {
  GameConfig get _cfg => widget.config;
  String get _name => _cfg.players.isEmpty ? AppState.owner : _cfg.players.first;
  String get _id => HistoryStore.playerId(_name);

  late DoublesProStore _store = DoublesProStore(_name);
  late GameLog _log = GameLog(seed: widget.paused?.seed, replayLog: widget.paused?.log);
  late int _option = _cfg.option.clamp(0, DpBlock.values.length);
  late DoublesProSession _g = _newSession();

  late bool _started = widget.paused != null;
  final List<BoardHit> _hits = [];
  DartThrow? _tagDart;
  int _tagKey = 0;
  Timer? _tagTimer;
  Timer? _endTimer;
  bool _showEnd = false;
  bool _saved = false;

  List<DpBlock> get _blocks => _option == 0 ? DpBlock.values : [DpBlock.values[_option - 1]];

  DoublesProSession _newSession() => DoublesProSession(_name, blocks: _blocks, seed: _log.seed);

  GameConfig get _pauseConfig =>
      GameConfig(players: _cfg.players, mode: GameMode.doublesPro, practice: _cfg.practice, option: _option);

  @override
  void initState() {
    super.initState();
    AppState.lastGame = widget.config;
    CamLink.instance
      ..debugGame = widget.config.label
      ..onDart = _camDart
      ..onTakeout = _camTakeout;
    if (widget.paused != null) {
      _log.replay(_apply);
      PausedGame.clear();
    }
    _sync();
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

  // MARK: Jeu

  void _start(int option) {
    setState(() {
      _option = option;
      _g = _newSession();
      _started = true;
    });
    _sync();
  }

  void _apply(Map<String, Object?> e) {
    switch (e['t']) {
      case 'd':
        _throw(GameLog.dartOf(e), GameLog.offsetOf(e) ?? boardPositionFor(GameLog.dartOf(e)));
      case 'c':
        _applyCorrection(GameLog.correctionOf(e));
      case 'u':
        _applyRemoval(e['i'] as int);
      case 'e':
        _nextVolley();
    }
  }

  void _pause() {
    _log.pause(_pauseConfig);
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
    _sync();
    _endTimer?.cancel();
    if (!_g.isFinished) {
      _showEnd = false;
      return;
    }
    AppState.lastResult = '$_name : Doubles Pro, ${_g.scoreOf(0)} % de doubles';
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

  /// Annuler : la fléchette est retirée du tour (coup fantôme, annulation), le joueur la relance.
  Future<void> _cancel() async {
    if (_showEnd || !_started) return;
    final c = await askCancelDart(context, _g.currentTurn, List.of(_hits));
    if (c == null || !mounted) return;
    _applyRemoval(c.index);
  }

  void _applyRemoval(int index) {
    _log.add(GameLog.removal(index));
    setState(() {
      _g.removeAt(index);
      final kept = hitsWithout(_hits, index, _g.currentTurn);
      _hits
        ..clear()
        ..addAll(kept);
      _tagDart = null;
    });
    _afterDart();
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

  void _again() {
    _endTimer?.cancel();
    _save();
    setState(() {
      _saved = false;
      _store = DoublesProStore(_name);
      _log = GameLog();
      _g = _newSession();
      _hits.clear();
      _tagDart = null;
      _showEnd = false;
      _started = false;
    });
    _sync();
  }

  /// Projecteur et caméras : le double visé allumé, la sortie à l'échelle.
  void _sync() {
    final g = _g;
    final playing = _started && !g.isFinished;
    if (!g.awaitingNextPlayer) {
      final aim = playing ? g.aim : null;
      final route = playing && g.block == DpBlock.ladder ? _route : null;
      CamLink.instance.setGameInfo(
        'Doubles Pro',
        checkout: route == null || route.length < 2 ? null : [for (final d in route) d.label],
        coachCell: aim?.label ?? route?.first.label,
        training: true,
      );
    } else {
      CamLink.instance.setGameInfo('Doubles Pro', wait: true, training: true);
    }
    CamLink.instance.setPlaying(playing);
  }

  /// Échelle : sortie conseillée pour le reste.
  List<DartThrow>? get _route {
    final c = _g.current;
    if (c == null || _g.block != DpBlock.ladder) return null;
    return suggestCheckout(_g.remaining, dartsLeft: math.min(3 - _g.currentTurn.length, dpLadderDarts - c.darts));
  }

  // MARK: Historique

  static String _pct(int ok, int total) => total == 0 ? '-' : '${(ok * 100 / total).round()} %';

  static String _num(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

  /// Résultat court d'un bloc, pour l'accueil et le bilan.
  String _blockResult(DpBlock b) {
    final g = _g;
    switch (b) {
      case DpBlock.diagnostic:
        final h = g.hitsOf(b);
        return '${h.ok}/${h.total}';
      case DpBlock.chains:
        final r = g.runsOf(b);
        final avg = g.chainAverage;
        return avg == null ? '${r.ok}/${r.total}' : '${_num(avg)} fl.';
      case DpBlock.random:
        final h = g.hitsOf(b);
        return _pct(h.ok, h.total);
      case DpBlock.ladder:
        return '${g.bestLadder ?? '-'}';
    }
  }

  void _save() {
    if (_log.replaying || !_started) return;
    final g = _g;
    if (!g.isFinished || _saved) return;
    _saved = true;
    final ok = g.shots.where((s) => s.ok).length;
    final pct = g.scoreOf(0);
    final darts = g.turnsOf(0).fold<int>(0, (n, t) => n + t.length);
    Map<String, Object?> bias(DartThrow t) {
      final d = g.diagnosticOf(t);
      return {
        'hit': d.hit,
        'out': d.outside,
        'in': d.inside,
        'side': d.side,
        'radial': double.parse(d.bias.radial.toStringAsFixed(1)),
        'tangential': double.parse(d.bias.tangential.toStringAsFixed(1)),
        'spread': double.parse(d.bias.spread.toStringAsFixed(1)),
      };
    }

    HistoryStore.instance.add({
      'id': '${DateTime.now().millisecondsSinceEpoch}',
      'at': DateTime.now().toIso8601String(),
      'mode': 'Doubles Pro',
      'kind': GameMode.doublesPro.name,
      'training': true,
      'option': _option,
      'winner': null,
      'players': [
        {
          'id': _id,
          'name': _name,
          'won': false,
          'darts': darts,
          'score': pct,
          'value': pct.toDouble(),
          'valueLabel': '% doubles',
          'doublePct': pct,
          'doubleOk': ok,
          'doubleTotal': g.shots.length,
          'blocks': {for (final b in g.blocks) b.name: _blockResult(b)},
          if (g.blocks.contains(DpBlock.diagnostic))
            'diagnostic': {for (final t in dpDiagnosticTargets) t.label: bias(t)},
          if (g.chainAverage != null) 'chainAvg': double.parse(g.chainAverage!.toStringAsFixed(2)),
          'ladderBest': ?g.bestLadder,
          'shots': [for (final s in g.shots) s.toJson()],
          'runs': [for (final r in g.runs) r.toJson()],
        },
      ],
    });
  }

  // MARK: Écran

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Td.beton,
      body: Stack(
        children: [
          Stage(
            child: Padding(padding: const EdgeInsets.all(Td.s3), child: _started ? _session() : _home()),
          ),
          if (_showEnd && _g.isFinished) Positioned.fill(child: _end()),
        ],
      ),
    );
  }

  // MARK: Accueil

  Widget _home() {
    final p = _store.coach.profile;
    final pct = p.attempts == 0 ? null : (p.hits * 100 / p.attempts).round();
    final weak = p.skills.values.where((s) => s.attempts >= 5).toList()..sort((a, b) => a.rate.compareTo(b.rate));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Td.s3,
      children: [
        SizedBox(
          width: 300,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Td.s3,
            children: [
              SizedBox(
                height: Td.ciblePi,
                child: Row(
                  spacing: Td.s3,
                  children: [
                    TdIconButton(
                      icon: LucideIcons.chevronLeft,
                      label: 'Retour',
                      size: Td.ciblePi,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Entraînement · Finir', style: TdText.inter(12, 16, 500, Td.ink3)),
                          Text('Doubles Pro', style: TdText.inter(28, 34, 700, Td.ink)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _glass(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Tes doubles', style: TdText.inter(15, 20, 400, Td.ink2)),
                      _bigPct(pct == null ? '-' : '$pct', unit: pct == null ? '' : '%'),
                      Text(
                        p.attempts == 0
                            ? 'Pas encore de fléchette sur un double'
                            : '${p.attempts} fléchettes sur un double',
                        style: TdText.inter(13, 18, 400, Td.ink3),
                      ),
                      const Spacer(),
                      _benchRow('Toi', pct ?? 0, Td.fluo),
                      for (final (n, v) in dpBenchmarks)
                        _benchRow(n, v, v >= 50 ? Td.crepuscule : (v >= 40 ? Td.sunset : Td.ink3)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Td.s2,
            children: [
              SizedBox(
                height: 28,
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Text('Séance du jour · 20 min', style: TdText.inter(15, 20, 400, Td.ink2)),
                ),
              ),
              for (final b in DpBlock.values) Expanded(child: _blockRow(b)),
            ],
          ),
        ),
        SizedBox(
          width: 260,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Td.s2,
            children: [
              const Align(alignment: Alignment.centerRight, child: VolumeButton()),
              _card(
                'Série en cours',
                '${_store.streak} jour${_store.streak > 1 ? 's' : ''}',
                'Record ${_store.bestStreak} jours',
              ),
              _card(
                'Double le plus faible',
                weak.isEmpty ? '-' : (weak.first.target.sector == 25 ? 'Bull' : weak.first.label),
                weak.isEmpty
                    ? '5 fléchettes par double minimum'
                    : '${weak.first.pct} % sur ${weak.first.attempts} fléchettes',
              ),
              const Spacer(),
              TdButton(label: 'Lancer', icon: LucideIcons.play, height: Td.ciblePiFort, onPressed: () => _start(0)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _blockRow(DpBlock b) {
    final last = _store.lastOf(b);
    return Material(
      color: Td.asphalte,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Td.rLg),
        side: const BorderSide(color: Td.bord),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(Td.rLg),
        onTap: () => _start(b.index + 1),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Td.s4, vertical: Td.s2),
          child: Row(
            spacing: Td.s4,
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Td.sunsetFond, borderRadius: BorderRadius.circular(Td.rMd)),
                child: Text('${b.index + 1}', style: TdText.rounded(24, 900, Td.sunset)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(b.title, maxLines: 1, style: TdText.inter(17, 22, 600, Td.ink)),
                    Text(
                      b.desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TdText.inter(13, 18, 400, Td.ink3),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(last ?? '-', style: TdText.rounded(22, 800, Td.ink)),
                  Text('dernière fois', style: TdText.inter(12, 16, 500, Td.ink3)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _benchRow(String name, int v, Color c) => Padding(
    padding: const EdgeInsets.only(top: Td.s2),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Td.s1,
      children: [
        Row(
          children: [
            Expanded(child: Text(name, style: TdText.inter(13, 18, 400, Td.ink2))),
            Text('$v %', style: TdText.inter(13, 18, 600, Td.ink)),
          ],
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Container(
            height: 8,
            color: Td.verreLeger,
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: (v / 50).clamp(0.0, 1.0),
              heightFactor: 1,
              child: ColoredBox(color: c),
            ),
          ),
        ),
      ],
    ),
  );

  // MARK: Pendant la séance

  Widget _session() => switch (_g.block) {
    DpBlock.diagnostic => _diagnostic(),
    _ => _boardLayout(),
  };

  /// Haut de colonne : arrêter, bloc et titre.
  Widget _header(String title) => SizedBox(
    height: Td.ciblePi,
    child: Row(
      spacing: Td.s2,
      children: [
        StopGameButton(onPause: _g.isFinished ? null : _pause),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Bloc ${math.min(_g.blockIndex + 1, _blocks.length)} sur ${_blocks.length} · ${_g.block == DpBlock.ladder ? 'Échelle' : _g.block.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TdText.inter(12, 16, 500, Td.ink3),
              ),
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TdText.inter(26, 32, 700, Td.ink)),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _diagnostic() {
    final g = _g;
    final t = g.aim ?? dpDiagnosticTargets.last;
    final d = g.diagnosticOf(t);
    final i = dpDiagnosticTargets.indexOf(t);
    final thrown = g.shotsOf(DpBlock.diagnostic).where((s) => s.aim == t).toList();
    final b = d.bias;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Td.s3,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Td.s3,
            children: [
              Row(
                children: [
                  Expanded(child: _header('Double ${t.sector}')),
                  for (var k = 0; k < dpDiagnosticTargets.length; k++) ...[
                    const SizedBox(width: Td.s2),
                    _chip('${dpDiagnosticTargets[k].label} · $dpDiagnosticDarts', k == i),
                  ],
                ],
              ),
              Expanded(
                child: _DoubleZoom(target: t, shots: thrown, onTap: _onBoardTap),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 300,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Td.s2,
            children: [
              _glass(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Dans le double', style: TdText.inter(15, 20, 400, Td.ink2)),
                    _bigPct('${d.hit}', unit: '/ ${thrown.length}'),
                    Text(
                      'Dehors ${d.outside} · Dedans ${d.inside + d.side} · ${dpDiagnosticDarts - thrown.length} restante${dpDiagnosticDarts - thrown.length > 1 ? 's' : ''}',
                      style: TdText.inter(13, 18, 400, Td.ink3),
                    ),
                  ],
                ),
              ),
              _tile(
                'Tendance',
                b.placed < 3
                    ? [Text('3 fléchettes minimum', style: TdText.inter(15, 20, 400, Td.ink2))]
                    : [
                        _biasLine(b.radial, LucideIcons.arrowUp, LucideIcons.arrowDown, 'dehors', 'dedans'),
                        _biasLine(
                          b.tangential,
                          LucideIcons.rotateCw,
                          LucideIcons.rotateCcw,
                          'sens horaire',
                          'sens inverse',
                        ),
                        Text('Dispersion ${_num(b.spread)} mm', style: TdText.inter(13, 18, 400, Td.ink3)),
                      ],
              ),
              const Spacer(),
              DartSlots(slots: _slots),
              _actions(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _biasLine(double v, IconData plus, IconData minus, String pos, String neg) => Row(
    spacing: Td.s2,
    children: [
      Icon(v >= 0 ? plus : minus, size: 20, color: Td.ink),
      Text(
        v.abs() < 0.5 ? 'Centré' : '${_num(v.abs())} mm ${v >= 0 ? pos : neg}',
        style: TdText.inter(20, 25, 600, Td.ink),
      ),
    ],
  );

  /// Chaînes, aléatoire, échelle : colonne de suivi, plateau, score.
  Widget _boardLayout() => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: Td.s3,
    children: [
      SizedBox(width: 236, child: _left()),
      Expanded(child: _board()),
      SizedBox(width: 300, child: _right()),
    ],
  );

  Widget _left() {
    final g = _g;
    switch (g.block) {
      case DpBlock.chains:
        final start = g.current?.start ?? dpChainStarts[math.min(g.runIndex, dpChainStarts.length - 1)];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Td.s2,
          children: [
            _header('Chaîne du ${start ~/ 2}'),
            for (final s in _chainSteps(start)) Expanded(child: _step(s.$1, s.$2, s.$3)),
          ],
        );
      case DpBlock.random:
        final h = g.hitsOf(DpBlock.random);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Td.s2,
          children: [
            _header('${math.min(g.dartsInBlock + 1, dpRandomDarts)} / $dpRandomDarts'),
            _progress(g.dartsInBlock / dpRandomDarts),
            _glass(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Réussite', style: TdText.inter(15, 20, 400, Td.ink2)),
                  _bigPct(h.total == 0 ? '-' : '${(h.ok * 100 / h.total).round()}', unit: h.total == 0 ? '' : '%'),
                  Text('${h.ok} sur ${h.total}', style: TdText.inter(13, 18, 400, Td.ink3)),
                ],
              ),
            ),
            KpiTile(label: 'Objectif pro', value: '42 %', glass: false),
            const Spacer(),
          ],
        );
      case DpBlock.ladder:
      case DpBlock.diagnostic:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 6,
          children: [
            _header('Marche ${g.rung + 1} / ${dpLadder.length}'),
            for (var i = dpLadder.length - 1; i >= 0; i--) Expanded(child: _rung(i)),
          ],
        );
    }
  }

  /// Étapes de la chaîne : (double, texte, état 0 fait, 1 au tir, 2 à venir).
  List<(String, String, int)> _chainSteps(int start) {
    final out = <(String, String, int)>[];
    final rem = _g.remaining;
    for (var v = start; v >= 2 && v.isEven; v ~/= 2) {
      final state = v > rem ? 0 : (v == rem ? 1 : 2);
      out.add(('D${v ~/ 2}', state == 0 ? 'Simple, descendu' : (state == 1 ? 'Au tir' : ''), state));
    }
    return out;
  }

  Widget _rung(int i) {
    final g = _g;
    final best = g.bestRung;
    final cur = i == g.rung && !g.isFinished;
    final done = best != null && i <= best && !cur;
    final last = g.runs.where((r) => r.block == DpBlock.ladder && r.ok == true && r.start == dpLadder[i]).lastOrNull;
    final rec = _ladderRecord;
    return _step(
      '${dpLadder[i]}',
      cur ? 'Au tir' : (done && last != null ? 'Fait, ${last.darts} fl.' : (rec == dpLadder[i] ? 'Record' : '')),
      cur ? 1 : (done ? 0 : 2),
      doneColor: Td.succesFond,
    );
  }

  /// Meilleure marche de toutes les séances.
  late final int? _ladderRecord = () {
    int? best;
    for (final e in _store.sessions) {
      final v = (e.p['ladderBest'] as num?)?.toInt();
      if (v != null && (best == null || v > best)) best = v;
    }
    return best;
  }();

  Widget _step(String label, String state, int s, {Color? doneColor}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: Td.s4),
    decoration: BoxDecoration(
      color: s == 1 ? Td.sunsetFond : (s == 0 ? (doneColor ?? Td.asphalte) : Td.verreLeger),
      borderRadius: BorderRadius.circular(Td.rLg),
      border: Border.all(color: s == 1 ? Td.sunset : Td.bord, width: s == 1 ? 2 : 1),
    ),
    child: Row(
      children: [
        Text(
          label,
          style: TdText.rounded(26, 900, s == 2 ? Td.ink2 : (s == 0 && doneColor == null ? Td.ink3 : Td.ink)),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            state,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TdText.inter(13, 18, 600, s == 0 && doneColor == null ? Td.ink3 : Td.ink),
          ),
        ),
      ],
    ),
  );

  Widget _board() {
    final g = _g;
    final aim = _started && !g.isFinished ? (g.aim ?? _route?.first) : null;
    final d = _tagDart;
    final random = g.block == DpBlock.random;
    return Column(
      children: [
        if (random && aim != null) ...[
          Text('Vise', style: TdText.inter(15, 20, 400, Td.ink2)),
          Text(
            aim.sector == 25 ? 'Bull' : aim.label,
            style: TdText.rounded(
              96,
              900,
              Td.fluo,
              height: 96,
            ).copyWith(shadows: const [Shadow(color: Color(0x66FFE14D), blurRadius: 20)]),
          ),
        ],
        Expanded(
          child: Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Dartboard(hits: _hits, aimed: aim, dim: aim != null, onTapBoard: _onBoardTap),
                if (d != null)
                  Positioned(
                    left: -40,
                    right: -40,
                    top: d.isMiss ? null : 120,
                    bottom: d.isMiss ? 8 : null,
                    child: IgnorePointer(
                      child: Center(
                        child: HitTag.forDart(d, key: ValueKey(_tagKey), fontSize: d.isMiss ? 48 : 64),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _right() {
    final g = _g;
    final children = <Widget>[];
    switch (g.block) {
      case DpBlock.chains:
        final r = g.runsOf(DpBlock.chains);
        final avg = g.chainAverage;
        final last = g.shots.where((s) => s.block == DpBlock.chains).lastOrNull;
        children.addAll([
          _glass(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Il reste', style: TdText.inter(15, 20, 400, Td.ink2)),
                Text('${g.remaining}', style: TdText.rounded(88, 900, Td.ink, height: 88)),
                if (last != null && last.dart.multiplier == 1 && last.dart.sector == last.aim.sector && g.runDarts > 0)
                  Text(
                    '${last.dart.label}. Tu passes sur ${g.aim?.label ?? '-'}.',
                    style: TdText.inter(13, 18, 400, Td.ink3),
                  ),
              ],
            ),
          ),
          DartSlots(slots: _slots),
          Row(
            spacing: Td.s2,
            children: [
              Expanded(
                child: KpiTile(
                  label: 'Chaîne',
                  value: '${math.min(r.total + 1, dpChainStarts.length)} / ${dpChainStarts.length}',
                  glass: false,
                ),
              ),
              Expanded(
                child: KpiTile(label: 'Moyenne', value: avg == null ? '-' : '${_num(avg)} fl.', glass: false),
              ),
            ],
          ),
        ]);
      case DpBlock.random:
        children.addAll([
          SizedBox(
            height: 28,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Text('Cette séance, par double', style: TdText.inter(15, 20, 400, Td.ink2)),
            ),
          ),
          Expanded(child: _grid(g.shotsOf(DpBlock.random), current: g.aim, columns: 3)),
          Text('Touchés / tirés. Le prochain double reste caché.', style: TdText.inter(12, 16, 400, Td.ink3)),
          DartSlots(slots: _slots),
        ]);
      case DpBlock.ladder:
      case DpBlock.diagnostic:
        final c = g.current;
        final route = _route;
        children.addAll([
          _glass(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Il reste', style: TdText.inter(15, 20, 400, Td.ink2)),
                Text('${g.remaining}', style: TdText.rounded(88, 900, Td.ink, height: 88)),
                Text(
                  '${dpLadderDarts - (c?.darts ?? 0)} fléchette${dpLadderDarts - (c?.darts ?? 0) > 1 ? 's' : ''} sur $dpLadderDarts · essai ${math.min(g.runIndex + 1, dpLadderTries)} sur $dpLadderTries',
                  style: TdText.inter(13, 18, 400, Td.ink3),
                ),
              ],
            ),
          ),
          if (route != null) CheckoutHint(route: [for (final d in route) d.label]),
          DartSlots(slots: _slots),
        ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Td.s2,
      children: [...children, if (g.block != DpBlock.random) const Spacer(), _actions()],
    );
  }

  /// Corriger, hors cible, volée suivante.
  Widget _actions() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: Td.s2,
    children: [
      Row(
        spacing: Td.s2,
        children: [
          Expanded(child: _small('Corriger', LucideIcons.pencil, _correct)),
          Expanded(child: _small('Annuler', LucideIcons.undo2, _cancel)),
          Expanded(
            child: _small(
              'Hors cible',
              LucideIcons.target,
              _g.awaitingNextPlayer || _g.isFinished ? null : _outOfBoard,
            ),
          ),
        ],
      ),
      TdButton(
        label: _g.isFinished ? 'Bilan' : 'Volée suivante',
        icon: LucideIcons.arrowRight,
        variant: _g.awaitingNextPlayer || _g.isFinished ? TdButtonVariant.primary : TdButtonVariant.secondary,
        height: Td.ciblePi,
        onPressed: _nextVolley,
      ),
    ],
  );

  List<SlotData> get _slots {
    final turn = _g.currentTurn;
    final shots = _g.shots;
    // Les dernières fléchettes enregistrées correspondent au tour en cours (hors approche à l'échelle).
    bool hit(int i) {
      final d = turn[i];
      if (_g.block == DpBlock.ladder) return !d.isMiss;
      final k = shots.length - turn.length + i;
      return k >= 0 && k < shots.length && shots[k].ok;
    }

    return [
      for (var i = 0; i < 3; i++)
        if (i < turn.length)
          hit(i)
              ? SlotData(SlotState.hit, label: turn[i].label, value: turn[i].score)
              : SlotData(SlotState.miss, label: turn[i].label, value: 0)
        else if (i == turn.length && !_g.awaitingNextPlayer && !_g.isFinished)
          const SlotData(SlotState.current)
        else
          const SlotData(SlotState.empty),
    ];
  }

  // MARK: Bilan

  Widget _end() {
    final g = _g;
    final ok = g.shots.where((s) => s.ok).length;
    final pct = g.scoreOf(0);
    return Celebration(
      kind: CelebrationKind.win,
      winner: _name,
      tag: 'SÉANCE FINIE',
      copy:
          'Doubles ${_pct(ok, g.shots.length)} · ${[for (final b in g.blocks) '${b.title} ${_blockResult(b)}'].join(' · ')}.',
      stats: [
        CelebrationStat('Doubles', '$pct %'),
        for (final b in g.blocks) CelebrationStat(b.title, _blockResult(b)),
        CelebrationStat('Écart Humphries', '${pct - 42 >= 0 ? '+' : ''}${pct - 42} pts'),
      ],
      onAgain: _again,
      homeLabel: 'Terminer',
      onHome: () => Navigator.of(context).pop(),
    );
  }

  // MARK: Briques

  /// Bouton secondaire compact (deux par ligne dans la colonne de 300).
  Widget _small(String label, IconData icon, VoidCallback? onTap) => Material(
    color: Td.verreMoyen,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Td.rMd),
      side: const BorderSide(color: Td.verreBord),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(Td.rMd),
      onTap: onTap,
      child: SizedBox(
        height: 56,
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 6,
              children: [
                Icon(icon, size: 18, color: onTap == null ? Td.desactiveInk : Td.ink),
                Text(label, style: TdText.inter(17, 22, 600, onTap == null ? Td.desactiveInk : Td.ink)),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _glass(Widget child) => Container(
    padding: const EdgeInsets.all(Td.s5),
    decoration: BoxDecoration(
      color: Td.verreMoyen,
      borderRadius: BorderRadius.circular(Td.rXl),
      border: Border.all(color: Td.verreBord),
    ),
    child: child,
  );

  Widget _bigPct(String v, {String unit = '%'}) => Row(
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    spacing: Td.s1,
    children: [
      Text(v, style: TdText.rounded(88, 900, Td.ink, height: 88).copyWith(letterSpacing: -2)),
      Text(unit, style: TdText.rounded(36, 800, Td.ink2)),
    ],
  );

  Widget _card(String label, String value, String sub) => _tile(label, [
    Text(value, maxLines: 1, style: TdText.rounded(44, 800, Td.ink, height: 48)),
    Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TdText.inter(13, 18, 400, Td.ink3)),
  ]);

  Widget _tile(String label, List<Widget> children) => Container(
    padding: const EdgeInsets.symmetric(horizontal: Td.s4, vertical: Td.s3),
    decoration: BoxDecoration(
      color: Td.asphalte,
      borderRadius: BorderRadius.circular(Td.rLg),
      border: Border.all(color: Td.bord),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        Text(label, style: TdText.inter(12, 16, 500, Td.ink3)),
        ...children,
      ],
    ),
  );

  Widget _chip(String label, bool on) => Container(
    height: 40,
    padding: const EdgeInsets.symmetric(horizontal: Td.s4),
    alignment: Alignment.center,
    decoration: BoxDecoration(color: on ? Td.sunsetFond : Td.verreLeger, borderRadius: BorderRadius.circular(Td.rSm)),
    child: Text(label, style: TdText.inter(15, 20, 600, on ? Td.sunset : Td.ink2)),
  );

  Widget _progress(double k) => ClipRRect(
    borderRadius: BorderRadius.circular(4),
    child: Container(
      height: 8,
      color: Td.verreLeger,
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: k.clamp(0.0, 1.0),
        heightFactor: 1,
        child: const ColoredBox(color: Td.sunset),
      ),
    ),
  );

  /// Grille des 21 doubles : touchés / tirés.
  Widget _grid(Iterable<DpShot> shots, {DartThrow? current, int columns = 3}) {
    final per = <String, (int, int)>{};
    for (final s in shots) {
      final (h, n) = per[s.aim.label] ?? (0, 0);
      per[s.aim.label] = (h + (s.ok ? 1 : 0), n + 1);
    }
    final all = [for (var i = 1; i <= 20; i++) DartThrow.double(i), DartThrow.bull];
    return LayoutBuilder(
      builder: (_, c) {
        final rows = (all.length / columns).ceil();
        const gap = 6.0;
        final h = (c.maxHeight - gap * (rows - 1)) / rows;
        final w = (c.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final d in all)
              () {
                final v = per[d.label];
                final cur = d == current;
                final bg = cur
                    ? const Color(0x21FFE14D)
                    : v == null
                    ? Td.verreLeger
                    : (v.$1 > 0 ? Td.succesFond : Td.erreurFond);
                return Container(
                  width: w,
                  height: h,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(Td.rSm),
                    border: cur ? Border.all(color: Td.fluo, width: 2) : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        d.sector == 25 ? 'Bull' : d.label,
                        style: TdText.inter(13, 16, 700, v == null && !cur ? Td.ink3 : Td.ink),
                      ),
                      Text(
                        cur ? 'au tir' : (v == null ? '-' : '${v.$1}/${v.$2}'),
                        style: TdText.inter(12, 16, 500, v == null && !cur ? Td.ink3 : Td.ink),
                      ),
                    ],
                  ),
                );
              }(),
          ],
        );
      },
    );
  }
}

/// Zoom x10 sur un double : la bande du double, le centre, chaque fléchette au mm et le point moyen.
/// Toucher la zone lance une fléchette à cet endroit (sans caméras).
class _DoubleZoom extends StatelessWidget {
  const _DoubleZoom({required this.target, required this.shots, required this.onTap});

  final DartThrow target;
  final List<DpShot> shots;
  final ValueChanged<Offset> onTap;

  /// Pixels par mm.
  static const k = 10.0;

  /// Angle du milieu du secteur (radians, depuis le haut, sens horaire).
  double get _angle => sectors.indexOf(target.sector) * 18 * math.pi / 180;

  /// Point du zoom (px) vers la cible (mm, y vers le bas).
  Offset _toBoard(Offset p, Size s) {
    final t = (p.dx - s.width / 2) / k;
    final r = (s.height / 2 - p.dy) / k;
    final rr = doubleMidRadius + r;
    final a = _angle + t / rr;
    return Offset(rr * math.sin(a), -rr * math.cos(a));
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(Td.rXl),
      child: LayoutBuilder(
        builder: (_, c) {
          final size = Size(c.maxWidth, c.maxHeight);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (e) => onTap(_toBoard(e.localPosition, size)),
            child: CustomPaint(
              size: size,
              painter: _ZoomPainter(target: target, shots: shots),
              child: Stack(
                children: [
                  Positioned(left: 20, top: 16, child: _label('Zoom x10 · 1 case = 1 mm')),
                  Positioned(right: 20, top: 16, child: _label('Dehors, 0 point')),
                  Positioned(right: 20, bottom: 16, child: _label('Dedans, simple ${target.sector}')),
                  Positioned(
                    left: 20,
                    top: size.height / 2 - 10,
                    child: Text('Centre du double', style: TdText.inter(13, 18, 600, Td.onAccent)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _label(String t) => Text(t, style: TdText.inter(12, 16, 500, Td.ink3));
}

class _ZoomPainter extends CustomPainter {
  _ZoomPainter({required this.target, required this.shots});

  final DartThrow target;
  final List<DpShot> shots;

  @override
  void paint(Canvas canvas, Size size) {
    const k = _DoubleZoom.k;
    final cx = size.width / 2, cy = size.height / 2;
    canvas.drawRect(Offset.zero & size, Paint()..color = Td.betonNuit);
    // Simple, sous le double.
    canvas.drawRect(Rect.fromLTRB(0, cy + 4 * k, size.width, size.height), Paint()..color = Td.plateauNoir);
    // Le double, 8 mm.
    final even = sectors.indexOf(target.sector).isEven;
    canvas.drawRect(
      Rect.fromLTRB(0, cy - 4 * k, size.width, cy + 4 * k),
      Paint()..color = (even ? Td.plateauRouge : Td.plateauVert).withValues(alpha: 0.85),
    );
    final wire = Paint()
      ..color = Td.ink3
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, cy - 4 * k), Offset(size.width, cy - 4 * k), wire);
    canvas.drawLine(Offset(0, cy + 4 * k), Offset(size.width, cy + 4 * k), wire);
    // Fils des secteurs voisins, à 9° du milieu.
    final half = doubleMidRadius * 9 * math.pi / 180 * k;
    for (final x in [cx - half, cx + half]) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), wire);
    }
    // Centre du double.
    final dash = Paint()
      ..color = Td.ink.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 12) {
      canvas.drawLine(Offset(x, cy), Offset(x + 6, cy), dash);
    }
    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), Paint()..color = Td.bord);

    final placed = <Offset>[];
    for (final s in shots) {
      if (s.x == null || s.y == null) continue;
      final e = aimError(s.aim, s.x!, s.y!);
      final p = Offset(cx + e.tangential * k, cy - e.radial * k);
      placed.add(p);
      final c = switch (s.miss) {
        DpMiss.hit => Td.fluo,
        DpMiss.outside => Td.erreur,
        _ => Td.ink2,
      };
      canvas.drawCircle(p, 9, Paint()..color = c);
      canvas.drawCircle(
        p,
        9,
        Paint()
          ..color = Td.beton
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    if (placed.length >= 3) {
      final m = placed.fold(Offset.zero, (a, b) => a + b) / placed.length.toDouble();
      canvas.drawCircle(
        m,
        18,
        Paint()
          ..color = Td.ciel
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }

  @override
  bool shouldRepaint(_ZoomPainter old) => true;
}
