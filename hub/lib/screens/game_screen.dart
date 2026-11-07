import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:darts_engine/darts_engine.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../game_config.dart';
import '../history/history_store.dart';
import '../lobby/lobby.dart';
import '../theme/tokens.dart';
import '../widgets/avatar.dart';
import '../widgets/celebration.dart';
import '../widgets/dartboard.dart';
import '../widgets/game_widgets.dart';
import '../widgets/hit_tag.dart';
import '../widgets/logo.dart';
import '../widgets/player_card.dart';
import '../widgets/stage.dart';
import '../widgets/status_indicator.dart';
import '../widgets/td_button.dart';
import 'correction_screen.dart';

/// Partie 501 (planches J501*). En attendant le Pi 5, c'est un simulateur :
/// toucher le plateau lance une fléchette à cet endroit.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.config});

  final GameConfig config;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late X01Game _game = _newGame();
  int _leg = 1;
  int _starter = 0;
  final Map<String, int> _legsWon = {};
  final List<BoardHit> _hits = [];
  ThrowOutcome? _last;
  DartThrow? _tagDart;
  int _tagKey = 0;
  Timer? _tagTimer;
  Timer? _winTimer;

  /// Tours des manches déjà jouées, par joueur (pour les stats de victoire).
  final Map<String, List<List<List<DartThrow>>>> _pastLegs = {};
  bool _show180 = false;
  bool _showWin = false;

  GameConfig get _cfg => widget.config;

  /// Chaque manche, le joueur suivant commence.
  X01Game _newGame() {
    final names = _cfg.players;
    final order = [...names.sublist(_starter % names.length), ...names.sublist(0, _starter % names.length)];
    return X01Game(playerNames: order, startScore: _cfg.startScore, doubleOut: _cfg.doubleOut);
  }

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

  void _recordResult() {
    if (!_matchOver) return;
    final w = _game.winner!;
    final darts = w.turns.fold<int>(0, (n, t) => n + t.length);
    AppState.lastResult = '${w.name} a gagné, dernière manche en $darts fléchettes.';
  }

  bool get _matchOver => _game.winner != null && (_legsWon[_game.winner!.name] ?? 0) >= _cfg.legsToWin;

  @override
  void dispose() {
    _tagTimer?.cancel();
    _winTimer?.cancel();
    _save();
    if (Lobby.instance.stopGame == _stopFromPhone) Lobby.instance.stopGame = null;
    if (Lobby.instance.state == LobbyState.playing) Lobby.instance.close();
    super.dispose();
  }

  void _throw(DartThrow d, Offset pos) {
    if (_game.awaitingNextPlayer || _game.isFinished) return;
    setState(() {
      _last = _game.throwDart(d);
      if (_last == ThrowOutcome.checkout) {
        _legsWon.update(_game.winner!.name, (n) => n + 1, ifAbsent: () => 1);
        _recordResult();
      }
      final t = _game.currentTurn;
      if (_last != ThrowOutcome.bust && t.length == 3 && t.every((x) => x.sector == 20 && x.multiplier == 3)) {
        _show180 = true;
      }
      _hits.add(BoardHit(d, pos, _hits.length + 1));
      _tagDart = d;
      _tagKey++;
    });
    _tagTimer?.cancel();
    _tagTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted && _last != ThrowOutcome.bust) setState(() => _tagDart = null);
    });
    _scheduleWin();
  }

  /// La victoire s'affiche après le tag CHECKOUT.
  void _scheduleWin() {
    _winTimer?.cancel();
    if (!_matchOver) {
      _showWin = false;
      return;
    }
    _winTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted && _matchOver) setState(() => _showWin = true);
    });
  }

  /// Revanche : mêmes joueurs, on repart de zéro, le joueur suivant commence.
  void _rematch() {
    _winTimer?.cancel();
    _save();
    _saved = false;
    setState(() {
      _leg = 1;
      _starter++;
      _legsWon.clear();
      _pastLegs.clear();
      _game = _newGame();
      _hits.clear();
      _last = null;
      _tagDart = null;
      _showWin = false;
      _show180 = false;
    });
  }

  /// Chiffres d'un joueur sur toutes les manches : fléchettes, points, meilleur tour, essais et sorties
  /// réussies sur double, et le détail de chaque tour (pour l'historique).
  ({int darts, int scored, int best, int tries, int hits, List<Map<String, Object?>> rows}) _numbers(String name) {
    final legs = [...?_pastLegs[name], _game.players.firstWhere((p) => p.name == name).turns];
    var darts = 0, scored = 0, best = 0, tries = 0, hits = 0;
    final rows = <Map<String, Object?>>[];
    for (final (leg, turns) in legs.indexed) {
      var rem = _cfg.startScore;
      for (final turn in turns) {
        final start = rem;
        var sum = 0;
        var bust = false;
        for (final d in turn) {
          darts++;
          if (_cfg.doubleOut && ((rem <= 40 && rem.isEven && rem > 0) || rem == 50)) tries++;
          rem -= d.score;
          if (rem < 0 || (_cfg.doubleOut && rem == 1) || (_cfg.doubleOut && rem == 0 && !d.isDouble)) {
            bust = true;
            break;
          }
          sum += d.score;
          if (rem == 0) {
            if (_cfg.doubleOut) hits++;
            break;
          }
        }
        if (bust) {
          rem = start;
        } else {
          scored += sum;
          if (sum > best) best = sum;
        }
        rows.add({
          'leg': leg + 1,
          'darts': [for (final d in turn) d.label],
          'total': bust ? 0 : sum,
          'rest': rem,
          'bust': bust,
        });
      }
    }
    return (darts: darts, scored: scored, best: best, tries: tries, hits: hits, rows: rows);
  }

  List<CelebrationStat> _winStats(String name) {
    final n = _numbers(name);
    String fr(double v) => v.toStringAsFixed(1).replaceAll('.', ',');
    return [
      CelebrationStat('Moyenne 3 fléchettes', n.darts == 0 ? '0' : fr(n.scored / n.darts * 3)),
      CelebrationStat('Meilleur tour', '${n.best}'),
      if (_cfg.doubleOut) CelebrationStat('Checkout', n.tries == 0 ? '0 %' : '${(n.hits * 100 / n.tries).round()} %'),
      CelebrationStat('Fléchettes', '${n.darts}'),
    ];
  }

  bool _saved = false;

  /// Enregistre la partie finie dans l'historique (une fois, en quittant ou avant la revanche).
  void _save() {
    if (!_matchOver || _saved) return;
    _saved = true;
    final winner = _game.winner!.name;
    HistoryStore.instance.add({
      'id': '${DateTime.now().millisecondsSinceEpoch}',
      'at': DateTime.now().toIso8601String(),
      'mode': '${_cfg.startScore}',
      'kind': 'x01',
      'doubleOut': _cfg.doubleOut,
      'legsToWin': _cfg.legsToWin,
      'winner': winner,
      'players': [
        for (final name in _cfg.players)
          () {
            final n = _numbers(name);
            return {
              'id': HistoryStore.playerId(name),
              'name': name,
              'won': name == winner,
              'legs': _legsWon[name] ?? 0,
              'darts': n.darts,
              'scored': n.scored,
              'best': n.best,
              'tries': n.tries,
              'hits': n.hits,
              'value': n.darts == 0 ? 0 : n.scored / n.darts * 3,
              'valueLabel': 'moy.',
              'turns': n.rows,
            };
          }(),
      ],
    });
  }

  void _onBoardTap(Offset p) => _throw(dartAt(p), p);

  void _outOfBoard() {
    // Position hors du plateau, sous le secteur visé, pour l'impact rouge.
    _throw(const DartThrow.miss(), const Offset(38.7, 181.9));
  }

  Future<void> _correct() async {
    if (_matchOver) return;
    final c = await Navigator.of(context).push<Correction>(
      MaterialPageRoute(
        builder: (_) => CorrectionScreen(turn: _game.currentTurn, hits: List.of(_hits)),
      ),
    );
    if (c == null || !mounted) return;
    final hadWinner = _game.winner;
    setState(() {
      if (hadWinner != null) _legsWon.update(hadWinner.name, (n) => n - 1);
      _last = _game.correctDart(c.index, c.dart);
      if (_game.winner != null) {
        _legsWon.update(_game.winner!.name, (n) => n + 1, ifAbsent: () => 1);
        _recordResult();
      }
      // On garde la position touchée pour les fléchettes inchangées.
      final kept = <BoardHit>[];
      for (var i = 0; i < _game.currentTurn.length; i++) {
        final d = _game.currentTurn[i];
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
    if (_matchOver) {
      Navigator.of(context).pop();
      return;
    }
    if (_game.isFinished) {
      // Manche suivante.
      setState(() {
        for (final p in _game.players) {
          _pastLegs.putIfAbsent(p.name, () => []).add(List.of(p.turns));
        }
        _leg++;
        _starter++;
        _game = _newGame();
        _hits.clear();
        _last = null;
        _tagDart = null;
      });
      return;
    }
    setState(() {
      _game.nextPlayer();
      _hits.clear();
      _last = null;
      _tagDart = null;
    });
  }

  /// Envoie l'état de la partie au salon, pour les iPhone qui suivent.
  void _publish() {
    final lobby = Lobby.instance;
    if (lobby.state != LobbyState.playing) return;
    final g = _game;
    lobby.publishGame({
      'mode': '${_cfg.startScore}',
      'leg': _leg,
      'legsToWin': _cfg.legsToWin,
      'current': g.currentPlayer.name,
      'next': g.nextPlayerInLine.name,
      'turnScore': g.currentTurn.fold<int>(0, (n, d) => n + d.score),
      'darts': [
        for (final d in g.currentTurn) {'label': d.label, 'value': d.score},
      ],
      'bust': _last == ThrowOutcome.bust,
      'checkout': g.checkoutHint?.map((d) => d.label).toList(),
      'players': [
        for (final p in g.players)
          {
            'name': p.name,
            'remaining': p.remaining,
            'average': p.turns.isEmpty ? null : p.average,
            'legs': _legsWon[p.name] ?? 0,
          },
      ],
      'winner': _matchOver ? g.winner!.name : null,
      if (_matchOver)
        'stats': [
          for (final st in _winStats(g.winner!.name)) {'label': st.label, 'value': st.value},
        ],
    });
  }

  @override
  Widget build(BuildContext context) {
    _publish();
    final g = _game;
    final p = g.currentPlayer;
    final turn = g.currentTurn;
    final bust = _last == ThrowOutcome.bust;
    final over = g.awaitingNextPlayer && !bust && !g.isFinished;
    final hint = g.checkoutHint;
    final turnScore = turn.fold<int>(0, (n, d) => n + d.score);

    final slots = [
      for (var i = 0; i < 3; i++)
        if (i < turn.length)
          bust && i == turn.length - 1
              ? SlotData(SlotState.error, label: turn[i].label, value: turn[i].score)
              : turn[i].isMiss
              ? const SlotData(SlotState.miss)
              : SlotData(
                  SlotState.hit,
                  label: turn[i].label,
                  value: turn[i].score,
                  highlight: i == turn.length - 1 && turn[i].multiplier == 3 && _tagDart != null,
                )
        else if (i == turn.length && !g.awaitingNextPlayer)
          const SlotData(SlotState.current)
        else
          const SlotData(SlotState.empty),
    ];

    final ScoreState scoreState = bust
        ? ScoreState.bust
        : hint != null
        ? ScoreState.out
        : ScoreState.normal;
    final String sub = bust
        ? 'Le tour ne compte pas'
        : over
        ? 'Tour: $turnScore'
        : hint != null && turn.isEmpty
        ? 'Sortie possible en ${hint.length}'
        : 'Début de tour: ${g.turnStartScore}';

    final Widget info;
    if (g.isFinished) {
      final won = _legsWon[p.name] ?? 0;
      info = TdBanner(
        text: _matchOver
            ? '${p.name} gagne la partie, $won manche${won > 1 ? 's' : ''} à ${_cfg.legsToWin == won ? _bestOther() : 0}.'
            : '${p.name} prend la manche $_leg. $won sur ${_cfg.legsToWin}.',
        error: false,
      );
    } else if (bust) {
      info = TdBanner(text: 'Bust. On reprend à ${g.turnStartScore}.');
    } else if (over) {
      info = Text('Le tour passe tout seul dès que la cible est vide.', style: TdText.inter(15, 20, 400, Td.ink2));
    } else if (turn.isNotEmpty && turn.last.isMiss) {
      info = TdToast(
        title: 'Fléchette ${turn.length} hors cible',
        body: "Compte zéro. Touche Corriger si c'était une erreur.",
      );
    } else if (hint != null) {
      info = CheckoutHint(route: [for (final d in hint) d.label == 'BULL' ? 'Bull' : d.label.replaceFirst('S', '')]);
    } else if (turn.isNotEmpty) {
      info = Text('Tour en cours: $turnScore', style: TdText.inter(15, 20, 400, Td.ink2));
    } else {
      info = const SizedBox(height: 20);
    }

    final players = [
      for (var i = 0; i < g.players.length; i++)
        PlayerSummary(
          g.players[i].name,
          average: g.players[i].turns.isEmpty ? null : g.players[i].average,
          score: g.players[i].remaining,
          status: g.winner == g.players[i]
              ? PlayerStatus.winner
              : i == g.currentIndex
              ? PlayerStatus.active
              : PlayerStatus.waiting,
        ),
    ];

    final board = Stage(
      child: Padding(
        padding: const EdgeInsets.all(Td.s3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Colonne joueurs (236 px)
            SizedBox(
              width: 236,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onLongPress: () => Navigator.of(context).pop(),
                        child: const Logo(variant: LogoVariant.icon, height: 44),
                      ),
                      const SizedBox(width: Td.s2),
                      const StopGameButton(),
                      const Spacer(),
                      Text('${_cfg.startScore} · Manche $_leg', style: TdText.inter(15, 20, 400, Td.ink2)),
                    ],
                  ),
                  const SizedBox(height: Td.s3),
                  for (final pl in players) ...[PlayerCard(player: pl), const SizedBox(height: Td.s2)],
                  const Spacer(),
                  const Wrap(
                    spacing: Td.s2,
                    runSpacing: Td.s2,
                    children: [
                      StatusIndicator(kind: StatusKind.camera, compact: true, label: 'Caméra 1'),
                      StatusIndicator(kind: StatusKind.camera, compact: true, label: 'Caméra 2'),
                      StatusIndicator(kind: StatusKind.camera, compact: true, label: 'Caméra 3'),
                      StatusIndicator(kind: StatusKind.wifi, compact: true),
                      StatusIndicator(kind: StatusKind.pi, compact: true, label: 'Pi 5'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: Td.s3),
            // Plateau
            Expanded(
              child: Center(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Dartboard(
                      hits: _hits,
                      aimed: turn.isEmpty && hint != null ? hint.first : null,
                      dim: bust || over || (_tagDart != null && !_tagDart!.isMiss),
                      onTapBoard: _onBoardTap,
                    ),
                    if (_tagDart != null && !bust)
                      Positioned(
                        left: -40,
                        right: -40,
                        top: _tagDart!.isMiss ? null : 440 * 0.36 - 60,
                        bottom: _tagDart!.isMiss ? 8 : null,
                        child: IgnorePointer(
                          child: Center(
                            child: g.isFinished
                                ? HitTag(
                                    key: ValueKey(_tagKey),
                                    kind: TagKind.checkout,
                                    text: 'CHECKOUT $turnScore',
                                    fontSize: 64,
                                  )
                                : HitTag.forDart(
                                    _tagDart!,
                                    key: ValueKey(_tagKey),
                                    fontSize: _tagDart!.isMiss ? 48 : 72,
                                  ),
                          ),
                        ),
                      ),
                    if (bust)
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 440 * 0.40 - 20,
                        child: IgnorePointer(
                          child: Center(
                            child: Transform.rotate(
                              angle: -6 * 3.14159 / 180,
                              child: Text(
                                'BUST',
                                style: const TextStyle(
                                  fontFamily: 'PermanentMarker',
                                  fontSize: 88,
                                  height: 92 / 88,
                                  color: Td.erreur,
                                  shadows: [Shadow(color: Color(0x99000000), blurRadius: 24, offset: Offset(0, 4))],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (over)
                      Positioned(
                        left: 24,
                        right: 24,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: _RemoveDarts(turnScore: turnScore, next: g.nextPlayerInLine),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: Td.s3),
            // Score et actions (300 px)
            SizedBox(
              width: 300,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ScoreDisplay(
                    value: p.remaining,
                    label: g.isFinished ? '${p.name} a gagné' : '${p.name}, il reste',
                    sub: g.isFinished ? 'Checkout' : sub,
                    state: g.isFinished ? ScoreState.out : scoreState,
                  ),
                  DartSlots(slots: slots),
                  info,
                  Column(
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
                      TdButton(
                        label: _matchOver
                            ? 'Terminer'
                            : g.isFinished
                            ? 'Manche suivante'
                            : 'Fin de tour',
                        icon: LucideIcons.arrowRight,
                        variant: g.awaitingNextPlayer ? TdButtonVariant.primary : TdButtonVariant.secondary,
                        height: Td.ciblePi,
                        onPressed: _endTurn,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return Scaffold(
      backgroundColor: Td.beton,
      body: Stack(
        children: [
          board,
          if (_showWin && _matchOver)
            Positioned.fill(
              child: Celebration(
                kind: CelebrationKind.win,
                winner: g.winner!.name,
                stats: _winStats(g.winner!.name),
                onAgain: _rematch,
                onHome: () => Navigator.of(context).pop(),
              ),
            )
          else if (_show180)
            Positioned.fill(
              child: Celebration(
                kind: CelebrationKind.oneEighty,
                winner: p.name,
                onTap: () => setState(() => _show180 = false),
              ),
            ),
        ],
      ),
    );
  }
}

extension on _GameScreenState {
  int _bestOther() {
    final w = _game.winner?.name;
    return _legsWon.entries.where((e) => e.key != w).fold<int>(0, (m, e) => e.value > m ? e.value : m);
  }
}

/// Panneau "Retire tes fléchettes." (planche J501FinTour).
class _RemoveDarts extends StatelessWidget {
  const _RemoveDarts({required this.turnScore, required this.next});

  final int turnScore;
  final X01Player next;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(Td.rXl),
      child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18), child: _panel()),
    );
  }

  Widget _panel() {
    return Container(
      padding: const EdgeInsets.all(Td.s6),
      decoration: BoxDecoration(
        color: Td.verreFort,
        borderRadius: BorderRadius.circular(Td.rXl),
        border: Border.all(color: Td.verreBord),
        boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 64, offset: Offset(0, 24))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.target, size: 36, color: Td.ciel),
          const SizedBox(height: Td.s3),
          Text('Retire tes fléchettes.', style: TdText.inter(28, 34, 700, Td.ink), textAlign: TextAlign.center),
          const SizedBox(height: Td.s3),
          Text(
            'Tour à $turnScore. Les caméras attendent une cible vide.',
            style: TdText.inter(17, 22, 400, Td.ink2),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Td.s4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Ensuite', style: TdText.inter(15, 20, 400, Td.ink2)),
              const SizedBox(width: Td.s2),
              Avatar(name: next.name, size: 28),
              const SizedBox(width: Td.s2),
              Text('${next.name}, ${next.remaining}', style: TdText.inter(15, 20, 700, Td.ink)),
            ],
          ),
        ],
      ),
    );
  }
}
