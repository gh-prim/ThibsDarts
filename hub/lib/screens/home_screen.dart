import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../game_config.dart';
import '../lobby/lobby.dart';
import '../theme/tokens.dart';
import '../tournament/tournament.dart';
import '../widgets/logo.dart';
import '../widgets/player_card.dart';
import '../widgets/stage.dart';
import '../widgets/status_indicator.dart';
import '../widgets/td_button.dart';
import 'mode_game_screen.dart';
import 'new_game_screen.dart';
import 'settings_screen.dart';
import 'salon_screen.dart';
import 'tournament_screen.dart';

/// Accueil : le Pi attend une partie.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Un iPhone crée une partie : on affiche son salon, seulement si l'accueil est à l'écran.
    Lobby.instance.remoteOpen = (cfg) {
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return false;
      _open(SalonScreen(config: cfg, opened: true));
      return true;
    };
  }

  @override
  void dispose() {
    Lobby.instance.remoteOpen = null;
    super.dispose();
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    // Une partie lancée remplace le salon : elle ferme le salon à sa sortie.
    if (Lobby.instance.state == LobbyState.open) Lobby.instance.close();
    if (mounted) setState(() {}); // la dernière partie a pu changer
  }

  /// Tournoi dont on a déjà fêté le vainqueur : l'accueil normal revient.
  String? _championSeen;

  @override
  Widget build(BuildContext context) {
    // Un tournoi lancé depuis l'iPhone prend l'accueil : annonce du match suivant, puis le vainqueur.
    return ListenableBuilder(
      listenable: TournamentStore.instance,
      builder: (context, _) {
        final t = TournamentStore.instance.current;
        final next = t?.state == 'en_cours' ? t!.next : null;
        if (next != null) {
          return TournamentMatchView(
            tournament: t!,
            match: next,
            onLaunch: () {
              final cfg = TournamentStore.instance.startMatch(next.id);
              if (cfg == null) return;
              Lobby.instance.playTournament(cfg);
              _open(gameScreenFor(cfg));
            },
          );
        }
        final champion = t?.finished == true ? t!.champion : null;
        if (champion != null && _championSeen != t!.id) {
          return TournamentChampionView(
            champion: TournamentStore.instance.nameOf(champion),
            onDone: () => setState(() => _championSeen = t.id),
          );
        }
        return _home(context);
      },
    );
  }

  Widget _home(BuildContext context) {
    final last = AppState.lastGame;
    final players = last?.players ?? [AppState.owner];
    return Scaffold(
      backgroundColor: Td.beton,
      body: Stage(
        child: Padding(
          padding: const EdgeInsets.all(Td.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Logo(height: 40),
                  const Spacer(),
                  // Les pastilles et la roue ouvrent les réglages (caméras en direct).
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _open(const SettingsScreen()),
                    child: const Row(
                      spacing: Td.s2,
                      children: [
                        StatusIndicator(kind: StatusKind.camera, compact: true, label: 'Caméra 1'),
                        StatusIndicator(kind: StatusKind.camera, compact: true, label: 'Caméra 2'),
                        StatusIndicator(kind: StatusKind.camera, compact: true, label: 'Caméra 3'),
                        StatusIndicator(kind: StatusKind.wifi, compact: true),
                        StatusIndicator(kind: StatusKind.pi, compact: true, label: 'Pi 5'),
                        _SettingsPill(),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Td.s5),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 13,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(last == null ? 'Prêt à jouer.' : "Le ${last.title} t'attend.", style: TdText.title),
                          const SizedBox(height: Td.s4),
                          Text(
                            last == null
                                ? 'Lance une partie ici. Les potes rejoignent depuis leur iPhone.'
                                : 'Dernière partie : ${last.label}, avec ${players.join(', ')}.'
                                      '${AppState.lastResult == null ? '' : ' ${AppState.lastResult}'}',
                            style: TdText.body,
                          ),
                          const SizedBox(height: Td.s6),
                          if (last != null) ...[
                            TdButton(
                              label: 'Rejouer',
                              icon: LucideIcons.refreshCw,
                              onPressed: () => _open(gameScreenFor(last)),
                            ),
                            const SizedBox(height: Td.s4),
                          ],
                          TdButton(
                            label: 'Nouvelle partie',
                            icon: LucideIcons.plus,
                            variant: last == null ? TdButtonVariant.primary : TdButtonVariant.secondary,
                            onPressed: () => _open(const NewGameScreen()),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Td.s5),
                    Expanded(
                      flex: 10,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: Td.s3,
                        children: [
                          Text(
                            last == null ? 'Sur ce ThibsDarts' : 'Joueurs de la dernière partie',
                            style: TdText.label,
                          ),
                          for (final p in players) PlayerCard(player: PlayerSummary(p)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  const Icon(LucideIcons.info, size: 16, color: Td.ink3),
                  const SizedBox(width: Td.s2),
                  Text("Tu peux aussi lancer la partie depuis l'iPhone.", style: TdText.caption),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pastille "Réglages", à côté des pastilles d'état.
class _SettingsPill extends StatelessWidget {
  const _SettingsPill();

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Réglages',
    child: Container(
      height: 32,
      width: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Td.verreLeger,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Td.verreBord),
      ),
      child: const Icon(LucideIcons.settings, size: 18, color: Td.ink2),
    ),
  );
}
