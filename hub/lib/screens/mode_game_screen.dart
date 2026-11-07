import 'dart:async';

import 'package:darts_engine/darts_engine.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../game_config.dart';
import '../history/history_store.dart';
import '../lobby/lobby.dart';
import '../tournament/tournament.dart';
import '../theme/tokens.dart';
import '../widgets/celebration.dart';
import '../widgets/dartboard.dart';
import '../widgets/game_widgets.dart';
import '../widgets/hit_tag.dart';
import '../widgets/logo.dart';
import '../widgets/mode_widgets.dart';
import '../widgets/player_card.dart';
import '../widgets/stage.dart';
import '../widgets/td_button.dart';
import 'correction_screen.dart';
import 'game_screen.dart';

/// Écran de jeu pour un X01 ou un autre mode, selon la config.
Widget gameScreenFor(GameConfig cfg) => cfg.mode == null ? GameScreen(config: cfg) : ModeGameScreen(config: cfg);

/// Cricket, Around the clock, Shanghai, Killer, Halve-it, Bob's 27 (planches du même nom).
/// En attendant le Pi 5, toucher le plateau lance une fléchette à cet endroit.
class ModeGameScreen extends StatefulWidget {
  const ModeGameScreen({super.key, required this.config, this.game});

  final GameConfig config;

  /// Partie déjà commencée (captures et tests).
  final TurnGame? game;

  @override
  State<ModeGameScreen> createState() => _ModeGameScreenState();
}

class _ModeGameScreenState extends State<ModeGameScreen> {
  late TurnGame _g = widget.game ?? _newGame();
  final List<BoardHit> _hits = [];
  DartThrow? _tagDart;
  int _tagKey = 0;
  Timer? _tagTimer;
  Timer? _winTimer;
  bool _showWin = false;

  GameConfig get _cfg => widget.config;
  GameMode get _mode => _cfg.mode!;

  TurnGame _newGame() => switch (_cfg.mode!) {
    GameMode.cricket => CricketGame(_cfg.players),
    GameMode.clock => ClockGame(_cfg.players),
    GameMode.shanghai => ShanghaiGame(_cfg.players),
    GameMode.killer => KillerGame(_cfg.players),
    GameMode.halveIt => HalveItGame(_cfg.players),
    GameMode.bobs27 => Bobs27Game(_cfg.players),
  };

  @override
  void initState() {
    super.initState();
    AppState.lastGame = widget.config;
    Lobby.instance.stopGame = _stopFromPhone;
  }

  /// Arrêt demandé depuis un iPhone du salon (déjà confirmé là-bas).
  void _stopFromPhone() {
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _tagTimer?.cancel();
    _winTimer?.cancel();
    _save();
    final match = _cfg.tournamentMatch;
    if (match != null) {
      // Match de tournoi en une manche : 1 à 0 pour le gagnant, rien en cas d'égalité ou d'arrêt.
      final w = _g.isFinished && !_g.isDraw ? _g.winner : null;
      TournamentStore.instance.endMatch(
        match,
        legsA: w == null ? null : (w == _cfg.players[0] ? 1 : 0),
        legsB: w == null ? null : (w == _cfg.players[1] ? 1 : 0),
      );
    }
    if (Lobby.instance.stopGame == _stopFromPhone) Lobby.instance.stopGame = null;
    if (Lobby.instance.state == LobbyState.playing) Lobby.instance.close();
    super.dispose();
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
    _scheduleWin();
  }

  void _scheduleWin() {
    _winTimer?.cancel();
    if (!_g.isFinished) {
      _showWin = false;
      return;
    }
    if (_g.winner != null) {
      AppState.lastResult = _g.isDraw ? 'Égalité au ${_cfg.title}.' : '${_g.winner} a gagné au ${_cfg.title}.';
    }
    _winTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted && _g.isFinished) setState(() => _showWin = true);
    });
  }

  void _onBoardTap(Offset p) => _throw(dartAt(p), p);

  void _outOfBoard() => _throw(const DartThrow.miss(), const Offset(38.7, 181.9));

  Future<void> _correct() async {
    if (_g.isFinished) return;
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
    _scheduleWin();
  }

  void _endTurn() {
    if (_g.isFinished) {
      setState(() => _showWin = true);
      return;
    }
    setState(() {
      _g.nextPlayer();
      _hits.clear();
      _tagDart = null;
    });
    _scheduleWin();
  }

  void _rematch() {
    _winTimer?.cancel();
    _save();
    _saved = false;
    setState(() {
      _g = _newGame();
      _hits.clear();
      _tagDart = null;
      _showWin = false;
    });
  }

  // MARK: Textes par mode

  bool get _solo => _g.names.length == 1;

  /// Fin sans vrai gagnant : égalité, ou partie solo.
  String? get _endTag => _g.isDraw ? 'ÉGALITÉ' : (_solo ? 'FINI' : null);

  String? get _endCopy {
    final g = _g;
    if (g.isDraw) {
      final who = [for (final i in g.winners) g.names[i]];
      return '${who.sublist(0, who.length - 1).join(', ')} et ${who.last} à égalité, ${g.scoreOf(g.winners.first)} points.';
    }
    if (_solo) {
      if (g is Bobs27Game && g.isOut(0)) return 'Sous zéro au ${_doubleLabel(g.target)}. On remet ça ?';
      if (g is ClockGame || g is ShanghaiGame && g.round <= g.rounds) return 'Bouclé en ${g.round} tours.';
      return 'Partie finie avec ${g.scoreOf(0)} points.';
    }
    return null;
  }

  String get _header => switch (_g) {
    final CricketGame g => 'Cricket · Tour ${g.round}',
    final ShanghaiGame g => 'Shanghai · Manche ${g.target}',
    final HalveItGame g => 'Halve-it · ${g.round.clamp(1, g.targets.length)} sur ${g.targets.length}',
    final Bobs27Game g => "Bob's 27 · ${_doubleLabel(g.target)}",
    _ => _cfg.title,
  };

  bool _saved = false;

  /// Enregistre la partie finie dans l'historique (une fois, en quittant ou avant la revanche).
  void _save() {
    final g = _g;
    if (!g.isFinished || _saved) return;
    _saved = true;
    HistoryStore.instance.add({
      'id': '${DateTime.now().millisecondsSinceEpoch}',
      'at': DateTime.now().toIso8601String(),
      'mode': _cfg.title,
      'kind': _mode.name,
      'winner': g.isDraw ? [for (final i in g.winners) g.names[i]].join(' et ') : g.winner,
      'players': [
        for (var i = 0; i < g.names.length; i++)
          () {
            final turns = g.turnsOf(i);
            final (value, label) = switch (g) {
              CricketGame() => (_marks(turns) / (turns.isEmpty ? 1 : turns.length), 'moy.'),
              final ClockGame c => (c.done(i).toDouble(), 'cibles'),
              KillerGame() => (g.scoreOf(i).toDouble(), 'vies'),
              _ => (g.scoreOf(i).toDouble(), 'pts'),
            };
            return {
              'id': HistoryStore.playerId(g.names[i]),
              'name': g.names[i],
              'won': g.winners.contains(i),
              'darts': turns.fold<int>(0, (n, t) => n + t.length),
              'score': g.scoreOf(i),
              'value': value,
              'valueLabel': label,
            };
          }(),
      ],
    });
  }

  /// Marques Cricket (20 à 15 et bull) dans une liste de tours.
  static int _marks(List<List<DartThrow>> turns) => [
    for (final t in turns)
      for (final d in t)
        if (!d.isMiss && CricketGame.numbers.contains(d.sector)) d.multiplier,
  ].fold(0, (a, b) => a + b);

  List<CelebrationStat> get _winStats => [
    CelebrationStat(_g is KillerGame ? 'Vies restantes' : 'Score', '${_g.scoreOf(_g.winnerIndex!)}'),
    CelebrationStat('Manches', '${_g.round}'),
  ];

  static String _doubleLabel(int sector) => sector == 25 ? 'Bull' : 'D$sector';

  /// Sous-ligne de chaque joueur dans la liste.
  String? _detail(int i) => switch (_g) {
    final ClockGame g => 'au ${g.target[i]}',
    final HalveItGame g => switch (g.halves[i]) {
      0 => 'aucun demi',
      1 => '1 demi',
      final n => '$n demis',
    },
    final Bobs27Game g => g.isOut(i) ? 'Éliminé' : _doubleLabel(g.target),
    final ShanghaiGame g => 'moy. ${_perRound(g.points[i], g.round)}',
    _ => null,
  };

  String _perRound(int pts, int round) {
    final played = (round - 1).clamp(1, 99);
    return (pts / played).toStringAsFixed(1).replaceAll('.', ',');
  }

  /// Envoie l'état aux iPhone du salon.
  void _publish() {
    final lobby = Lobby.instance;
    if (lobby.state != LobbyState.playing) return;
    final g = _g;
    final me = g.currentName;
    final (label, value, youLabel) = switch (g) {
      final ClockGame c => ('$me vise le', c.target[g.currentIndex], 'Tu vises le'),
      final ShanghaiGame s => ('Numéro de la manche', s.target, 'Numéro de la manche'),
      final KillerGame k => ('Vies de $me', k.life[g.currentIndex], 'Tes vies'),
      final HalveItGame h => (
        'Score de $me, cible ${h.target.label}',
        h.points[g.currentIndex],
        'Ton score, cible ${h.target.label}',
      ),
      final Bobs27Game b => (
        'Score de $me, cible ${_doubleLabel(b.target)}',
        b.points[g.currentIndex],
        'Ton score, cible ${_doubleLabel(b.target)}',
      ),
      _ => ('Score de $me', g.scoreOf(g.currentIndex), 'Ton score'),
    };
    lobby.publishGame({
      'mode': _cfg.title,
      'title': _header,
      'kind': _mode.name,
      'leg': g.round,
      'legsToWin': 1,
      'current': me,
      'next': g.nextName,
      'turnScore': g.currentTurn.fold<int>(0, (n, d) => n + d.score),
      'darts': [
        for (final d in g.currentTurn) {'label': d.label, 'value': d.score},
      ],
      'bust': false,
      'checkout': null,
      'scoreLabel': label,
      'scoreValue': value,
      'youLabel': youLabel,
      'players': [
        for (var i = 0; i < g.names.length; i++)
          {
            'name': g.names[i],
            'remaining': g.scoreOf(i),
            'average': null,
            'legs': 0,
            'detail': _detail(i) ?? (g is KillerGame ? _lives(g, i) : null),
            if (g is CricketGame) 'marks': [for (final m in g.marks[i]) m.clamp(0, 3)],
          },
      ],
      'winner': g.isDraw ? [for (final i in g.winners) g.names[i]].join(' et ') : g.winner,
      if (g.winner != null) ...{
        'endTag': _endTag,
        'endCopy': _endCopy,
        'stats': [
          for (final st in _winStats) {'label': st.label, 'value': st.value},
        ],
      },
    });
  }

  String _lives(KillerGame g, int i) {
    final n = g.life[i].clamp(0, g.lives);
    return '${'●' * n}${'○' * (g.lives - n)} $n ${n > 1 ? 'vies' : 'vie'}';
  }

  // MARK: Écran

  List<SlotData> get _slots {
    final turn = _g.currentTurn;
    return [
      for (var i = 0; i < 3; i++)
        if (i < turn.length)
          turn[i].isMiss || !_counts(turn[i])
              ? SlotData(SlotState.miss, label: turn[i].isMiss ? null : turn[i].label, value: 0)
              : SlotData(SlotState.hit, label: turn[i].label, value: _value(turn[i]))
        else if (i == turn.length && !_g.awaitingNextPlayer && !_g.isFinished)
          const SlotData(SlotState.current)
        else
          const SlotData(SlotState.empty),
    ];
  }

  /// La fléchette compte pour ce mode.
  bool _counts(DartThrow d) => switch (_g) {
    final CricketGame _ => CricketGame.numbers.contains(d.sector),
    final ClockGame _ => true,
    final ShanghaiGame g => d.sector == g.target,
    final KillerGame _ => d.isDouble,
    final HalveItGame g => g.target.matches(d),
    final Bobs27Game g => d.isDouble && d.sector == g.target,
    _ => true,
  };

  int _value(DartThrow d) => _g is CricketGame ? d.multiplier : d.score;

  @override
  Widget build(BuildContext context) {
    _publish();
    final g = _g;
    final board = Stage(
      child: Padding(padding: const EdgeInsets.all(Td.s3), child: g is CricketGame ? _cricket(g) : _threeColumns()),
    );
    return Scaffold(
      backgroundColor: Td.beton,
      body: Stack(
        children: [
          board,
          if (_showWin && g.winner != null)
            Positioned.fill(
              child: Celebration(
                kind: CelebrationKind.win,
                winner: g.winner!,
                tag: _endTag,
                copy: _endCopy,
                stats: _winStats,
                onAgain: _cfg.tournamentMatch == null ? _rematch : null,
                homeLabel: _cfg.tournamentMatch == null ? 'Accueil' : 'Suite du tournoi',
                onHome: () => Navigator.of(context).pop(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _top() => Row(
    children: [
      GestureDetector(
        onLongPress: () => Navigator.of(context).pop(),
        child: const Logo(variant: LogoVariant.icon, height: 44),
      ),
      const SizedBox(width: Td.s2),
      const StopGameButton(),
      const SizedBox(width: Td.s3),
      Expanded(
        child: Text(
          _header,
          textAlign: TextAlign.right,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TdText.inter(15, 20, 400, Td.ink2),
        ),
      ),
    ],
  );

  Widget _tag() {
    final d = _tagDart;
    if (d == null) return const SizedBox.shrink();
    return Positioned(
      left: -40,
      right: -40,
      top: d.isMiss ? null : 440 * 0.36 - 60,
      bottom: d.isMiss ? 8 : null,
      child: IgnorePointer(
        child: Center(
          child: HitTag.forDart(d, key: ValueKey(_tagKey), fontSize: d.isMiss ? 48 : 72),
        ),
      ),
    );
  }

  Widget _board({DartThrow? aimed, int? aimSector, Set<int> heat = const {}}) => Center(
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Dartboard(
          hits: _hits,
          aimed: aimed,
          aimSector: aimSector,
          heat: heat,
          dim: heat.isEmpty,
          onTapBoard: _onBoardTap,
        ),
        _tag(),
      ],
    ),
  );

  Widget _buttons({bool endTurn = true}) => Column(
    spacing: Td.s2,
    children: [
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
      if (endTurn) _endTurnButton(),
    ],
  );

  Widget _endTurnButton() => TdButton(
    label: _g.isFinished ? 'Terminer' : 'Fin de tour',
    icon: LucideIcons.arrowRight,
    variant: _g.awaitingNextPlayer || _g.isFinished ? TdButtonVariant.primary : TdButtonVariant.secondary,
    height: Td.ciblePi,
    onPressed: _endTurn,
  );

  // MARK: Cricket

  Widget _cricket(CricketGame g) {
    final open = {
      for (final n in CricketGame.numbers)
        if (g.isOpen(n)) n,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            spacing: Td.s2,
            children: [
              SizedBox(
                height: 40,
                child: Row(
                  children: [
                    GestureDetector(
                      onLongPress: () => Navigator.of(context).pop(),
                      child: const Logo(variant: LogoVariant.icon, height: 40),
                    ),
                    const SizedBox(width: Td.s2),
                    const StopGameButton(size: 40),
                    const SizedBox(width: Td.s3),
                    Text(_header, style: TdText.inter(15, 20, 400, Td.ink2)),
                    const Spacer(),
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(color: Td.sunset, borderRadius: BorderRadius.circular(3)),
                    ),
                    const SizedBox(width: Td.s2),
                    Text('Encore ouvert', style: TdText.inter(13, 18, 400, Td.ink2)),
                  ],
                ),
              ),
              Expanded(child: _board(heat: open)),
              Row(
                spacing: Td.s2,
                children: [
                  Expanded(
                    child: TdButton(
                      label: 'Corriger',
                      icon: LucideIcons.pencil,
                      variant: TdButtonVariant.secondary,
                      height: Td.ciblePi,
                      onPressed: _correct,
                    ),
                  ),
                  Expanded(
                    child: TdButton(
                      label: 'Hors cible',
                      icon: LucideIcons.target,
                      variant: TdButtonVariant.secondary,
                      height: Td.ciblePi,
                      onPressed: _outOfBoard,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: Td.s3),
        SizedBox(
          width: 440,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Td.s2,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: Td.s3, vertical: Td.s2),
                decoration: BoxDecoration(
                  color: Td.verreLeger,
                  borderRadius: BorderRadius.circular(Td.rLg),
                  border: Border.all(color: Td.verreBord),
                ),
                child: CricketBoard(
                  active: g.currentIndex,
                  players: [
                    for (var i = 0; i < g.names.length; i++)
                      CricketColumn(g.names[i], [for (final m in g.marks[i]) m.clamp(0, 3)], g.points[i]),
                  ],
                ),
              ),
              const Spacer(),
              DartSlots(slots: _slots),
              _endTurnButton(),
            ],
          ),
        ),
      ],
    );
  }

  // MARK: Autres modes : joueurs, plateau, panneau

  Widget _threeColumns() {
    final g = _g;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: g is KillerGame ? 260 : 236,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _top(),
              const SizedBox(height: Td.s3),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    spacing: Td.s2,
                    children: [
                      for (var i = 0; i < g.names.length; i++)
                        g is KillerGame
                            ? _killerRow(g, i)
                            : PlayerCard(
                                player: PlayerSummary(
                                  g.names[i],
                                  score: g.scoreOf(i),
                                  detail: _detail(i),
                                  status: g.winnerIndex == i
                                      ? PlayerStatus.winner
                                      : i == g.currentIndex
                                      ? PlayerStatus.active
                                      : PlayerStatus.waiting,
                                ),
                              ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: Td.s3),
        Expanded(
          child: _board(aimed: _aimed, aimSector: _aimSector),
        ),
        const SizedBox(width: Td.s3),
        SizedBox(
          width: 300,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ..._panel(),
              DartSlots(slots: _slots),
              _buttons(),
            ],
          ),
        ),
      ],
    );
  }

  DartThrow? get _aimed => switch (_g) {
    final ShanghaiGame g => _shanghaiNext(g),
    final Bobs27Game g => DartThrow(g.target, 2),
    final KillerGame g => _killerAim(g),
    _ => null,
  };

  int? get _aimSector => switch (_g) {
    final ClockGame g => g.target[g.currentIndex],
    final HalveItGame g => int.tryParse(g.target.label) ?? (g.target.label == 'Bull' ? 25 : null),
    _ => null,
  };

  DartThrow? _shanghaiNext(ShanghaiGame g) {
    final got = g.currentTurn.where((d) => d.sector == g.target).map((d) => d.multiplier).toSet();
    for (final m in [1, 2, 3]) {
      if (!got.contains(m)) return DartThrow(g.target, m);
    }
    return null;
  }

  DartThrow? _killerAim(KillerGame g) {
    final me = g.currentIndex;
    if (!g.killer[me]) return DartThrow(g.numbers[me], 2);
    for (var i = 1; i < g.names.length; i++) {
      final p = (me + i) % g.names.length;
      if (!g.isOut(p)) return DartThrow(g.numbers[p], 2);
    }
    return null;
  }

  List<Widget> _panel() {
    final g = _g;
    final me = g.currentName;
    final i = g.currentIndex;
    switch (g) {
      case final ClockGame c:
        return [
          ScoreDisplay(value: c.target[i], size: 88, label: '$me, vise le', sub: 'Simple, double ou triple'),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Td.s2,
            children: [
              Text('Progression, ${c.done(i)} sur 20', style: TdText.inter(13, 18, 600, Td.ink2)),
              GridView.count(
                crossAxisCount: 10,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                childAspectRatio: 26 / 26,
                children: [
                  for (var n = 1; n <= 20; n++)
                    Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: n <= c.done(i) ? Td.sunset : (n == c.target[i] ? Td.infoFond : Td.verreLeger),
                        borderRadius: BorderRadius.circular(6),
                        border: n == c.target[i] && n > c.done(i) ? Border.all(color: Td.ciel, width: 2) : null,
                      ),
                      child: Text(
                        '$n',
                        style: TdText.rounded(
                          13,
                          800,
                          n <= c.done(i) ? Td.onAccent : (n == c.target[i] ? Td.ciel : Td.ink3),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ];
      case final ShanghaiGame s:
        final got = s.currentTurn.where((d) => d.sector == s.target).map((d) => d.multiplier).toSet();
        return [
          ScoreDisplay(value: s.target, size: 88, label: 'Numéro de la manche', sub: '$me: ${s.points[i]} points'),
          _glass(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Td.s2,
              children: [
                Row(
                  spacing: Td.s2,
                  children: [
                    for (final (m, l) in const [(1, 'S'), (2, 'D'), (3, 'T')])
                      got.contains(m)
                          ? TdBadge(label: '$l${s.target}', icon: LucideIcons.check)
                          : TdBadge(label: '$l${s.target} ?', tone: BadgeTone.alerte),
                  ],
                ),
                Text(
                  'Simple, double et triple du ${s.target} dans le même tour: Shanghai, partie pliée.',
                  style: TdText.inter(15, 20, 400, Td.ink2),
                ),
              ],
            ),
          ),
        ];
      case final KillerGame k:
        final mine = k.numbers[i];
        return [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Td.s2,
            children: [
              Text('$me, ton numéro: $mine', style: TdText.inter(13, 18, 600, Td.ink2)),
              Text(k.killer[i] ? 'Tu es killer.' : 'Touche le D$mine.', style: TdText.inter(28, 34, 700, Td.ink)),
              Text(
                k.killer[i]
                    ? "Vise le double d'un adversaire pour lui retirer une vie. Évite le D$mine, c'est le tien."
                    : 'Ton double te rend killer. Après, chasse les autres.',
                style: TdText.inter(15, 20, 400, Td.ink2),
              ),
            ],
          ),
          if (k.lastEvent != null) TdBanner(text: k.lastEvent!, error: false) else const SizedBox(height: 44),
        ];
      case final HalveItGame h:
        final left = h.targets.skip(h.round).map((t) => t.label).toList();
        return [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Td.s1,
            children: [
              Text('Cible de la manche', style: TdText.inter(13, 18, 600, Td.ink2)),
              Text(h.target.label, style: TdText.rounded(64, 900, Td.ink, height: 64).copyWith(letterSpacing: -1)),
            ],
          ),
          ScoreDisplay(
            value: h.points[i],
            size: 48,
            label: 'Ton score',
            sub: left.isEmpty ? 'Dernière manche' : 'Ensuite: ${left.take(3).join(', ')}',
          ),
          const TdBanner(text: 'Rate tout et ton score est divisé par deux.', alert: true),
        ];
      case final Bobs27Game b:
        final delta = b.lastDelta[i];
        return [
          ScoreDisplay(value: b.points[i], size: 88, label: '$me, ton score', sub: 'Départ à 27'),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: Td.s4, vertical: Td.s3),
            decoration: BoxDecoration(
              color: delta == null || delta > 0 ? Td.succesFond : Td.erreurFond,
              borderRadius: BorderRadius.circular(Td.rLg),
            ),
            child: Row(
              spacing: Td.s3,
              children: [
                Icon(
                  delta == null || delta > 0 ? LucideIcons.check : LucideIcons.circleAlert,
                  size: 22,
                  color: delta == null || delta > 0 ? Td.succes : Td.erreur,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        delta == null
                            ? 'Vise le ${_doubleLabel(b.target)}'
                            : '${delta > 0 ? '+' : ''}$delta au dernier tour',
                        style: TdText.inter(17, 22, 700, Td.ink),
                      ),
                      Text(
                        'Rien touché au ${_doubleLabel(b.target)}: tu perds ${b.target * 2}.',
                        style: TdText.inter(13, 18, 400, Td.ink2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ];
      default:
        return [];
    }
  }

  Widget _glass(Widget child) => Container(
    padding: const EdgeInsets.symmetric(horizontal: Td.s4, vertical: Td.s3),
    decoration: BoxDecoration(
      color: Td.verreLeger,
      borderRadius: BorderRadius.circular(Td.rLg),
      border: Border.all(color: Td.verreBord),
    ),
    child: child,
  );

  Widget _killerRow(KillerGame g, int i) {
    final on = i == g.currentIndex;
    return Opacity(
      opacity: g.isOut(i) ? 0.38 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Td.s3, vertical: 10),
        decoration: BoxDecoration(
          color: Td.verreLeger,
          borderRadius: BorderRadius.circular(Td.rLg),
          border: Border.all(color: on ? Td.fluo : Td.verreBord),
          boxShadow: on
              ? const [BoxShadow(color: Color(0x66FFE14D), blurRadius: 20, blurStyle: BlurStyle.outer)]
              : null,
        ),
        child: Row(
          spacing: Td.s3,
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Td.asphalteHaut, borderRadius: BorderRadius.circular(Td.rMd)),
              child: Text('${g.numbers[i]}', style: TdText.rounded(24, 900, Td.ink)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Td.s1,
                children: [
                  Text(
                    g.names[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TdText.inter(17, 22, 600, Td.ink),
                  ),
                  Text(_lives(g, i), style: TdText.inter(12, 16, 400, Td.ink2)),
                ],
              ),
            ),
            if (g.killer[i] && !g.isOut(i)) const TdBadge(label: 'Killer', tone: BadgeTone.sunset, icon: killerIcon),
          ],
        ),
      ),
    );
  }
}
