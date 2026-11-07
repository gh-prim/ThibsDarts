import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/tokens.dart';
import '../tournament/tournament.dart';
import '../widgets/avatar.dart';
import '../widgets/stage.dart';
import '../widgets/td_button.dart';

/// Annonce du prochain match du tournoi (planche Tournoi, annonce du match).
class TournamentMatchView extends StatelessWidget {
  const TournamentMatchView({super.key, required this.tournament, required this.match, required this.onLaunch});

  final Tournament tournament;
  final TournamentMatch match;
  final VoidCallback onLaunch;

  @override
  Widget build(BuildContext context) {
    final store = TournamentStore.instance;
    final round = tournament.rounds[match.round];
    final a = store.nameOf(match.a!);
    final b = store.nameOf(match.b!);
    final legs = tournament.mode == 'cricket'
        ? 'Cricket · 1 manche'
        : '${tournament.mode} · ${tournament.legsToWin == 1 ? '1 manche' : '${tournament.legsToWin} manches gagnantes'}';
    return Scaffold(
      backgroundColor: Td.beton,
      body: Stage(
        child: Padding(
          padding: const EdgeInsets.all(Td.s5),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: Td.s5,
            children: [
              Transform.rotate(
                angle: -0.052,
                child: Text(
                  Tournament.roundTitle(round.length),
                  style: TdText.tag.copyWith(
                    fontSize: 56,
                    height: 61 / 56,
                    color: Td.sunset,
                    shadows: [Shadow(color: Td.sunset.withValues(alpha: 0.45), blurRadius: 32)],
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 48,
                children: [
                  _Side(name: a, line: store.lastWin(match.a!)),
                  Transform.rotate(
                    angle: -0.105,
                    child: Text(
                      'contre',
                      style: TdText.tag.copyWith(
                        fontSize: 47,
                        height: 1,
                        color: Td.fluo,
                        shadows: [Shadow(color: Td.fluo.withValues(alpha: 0.4), blurRadius: 20)],
                      ),
                    ),
                  ),
                  _Side(name: b, line: store.lastWin(match.b!)),
                ],
              ),
              Text('$legs · $a commence', style: TdText.inter(17, 22, 400, Td.ink2)),
              SizedBox(
                width: 600,
                child: Row(
                  spacing: Td.s3,
                  children: [
                    Expanded(
                      child: TdButton(
                        label: 'Voir le tableau',
                        icon: LucideIcons.users,
                        variant: TdButtonVariant.secondary,
                        height: Td.ciblePi,
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) => const TournamentBracketScreen()),
                        ),
                      ),
                    ),
                    Expanded(
                      child: TdButton(
                        label: 'Lancer le match',
                        icon: LucideIcons.play,
                        height: Td.ciblePi,
                        onPressed: onLaunch,
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
}

class _Side extends StatelessWidget {
  const _Side({required this.name, this.line});

  final String name;
  final String? line;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: Column(
        spacing: Td.s4,
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: Color(0x29FFFFFF), spreadRadius: 4),
                BoxShadow(color: Color(0x99000000), blurRadius: 64, offset: Offset(0, 24)),
              ],
            ),
            child: Avatar(name: name, size: 150),
          ),
          Column(
            spacing: Td.s1,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TdText.inter(34, 39, 800, Td.ink).copyWith(letterSpacing: -0.5),
              ),
              Text(line ?? ' ', style: TdText.inter(15, 20, 400, Td.ink2)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Fin du tournoi : le vainqueur.
class TournamentChampionView extends StatelessWidget {
  const TournamentChampionView({super.key, required this.champion, required this.onDone});

  final String champion;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Td.beton,
      body: Stage(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: Td.s5,
            children: [
              Transform.rotate(
                angle: -0.052,
                child: Text(
                  'Vainqueur du tournoi',
                  style: TdText.tag.copyWith(
                    fontSize: 56,
                    color: Td.sunset,
                    shadows: [Shadow(color: Td.sunset.withValues(alpha: 0.45), blurRadius: 32)],
                  ),
                ),
              ),
              Avatar(name: champion, size: 180, active: true),
              Text(champion, style: TdText.inter(40, 46, 800, Td.ink)),
              SizedBox(
                width: 320,
                child: TdButton(
                  label: 'Accueil',
                  icon: LucideIcons.house,
                  variant: TdButtonVariant.secondary,
                  height: Td.ciblePi,
                  onPressed: onDone,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tableau du tournoi sur l'écran du Pi : une colonne par tour.
class TournamentBracketScreen extends StatelessWidget {
  const TournamentBracketScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = TournamentStore.instance;
    return Scaffold(
      backgroundColor: Td.beton,
      body: Stage(
        child: Padding(
          padding: const EdgeInsets.all(Td.s5),
          child: ListenableBuilder(
            listenable: store,
            builder: (context, _) {
              final t = store.current;
              if (t == null) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Td.s4,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('Tableau du tournoi', style: TdText.headline)),
                      SizedBox(
                        width: 200,
                        child: TdButton(
                          label: 'Retour',
                          icon: LucideIcons.chevronLeft,
                          variant: TdButtonVariant.secondary,
                          height: 56,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ],
                  ),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: Td.s3,
                      children: [
                        for (final r in t.rounds)
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(Tournament.roundName(r.length), style: TdText.label),
                                const SizedBox(height: Td.s2),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [for (final m in r) _MatchCard(match: m, next: t.next?.id == m.id)],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.match, required this.next});

  final TournamentMatch match;
  final bool next;

  @override
  Widget build(BuildContext context) {
    final store = TournamentStore.instance;
    Widget line(String? id, int score, {bool top = false}) {
      final lost = match.done && match.winner != id;
      return Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: Td.s2),
        decoration: BoxDecoration(border: top ? null : const Border(top: BorderSide(color: Td.bord))),
        child: Opacity(
          opacity: lost ? 0.42 : 1,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  id == null ? (match.bye ? 'Place libre' : 'À venir') : store.nameOf(id),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TdText.inter(13, 18, match.winner == id && id != null ? 700 : 500, id == null ? Td.ink3 : Td.ink),
                ),
              ),
              if (match.done && !match.bye)
                Text('$score', style: TdText.rounded(15, 900, match.winner == id ? Td.sunset : Td.ink)),
            ],
          ),
        ),
      );
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Td.verreMoyen,
        borderRadius: BorderRadius.circular(Td.rSm),
        border: Border.all(color: next ? Td.sunset : Td.verreBord, width: next ? 2 : 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [line(match.a, match.scoreA, top: true), line(match.b, match.scoreB)],
      ),
    );
  }
}
