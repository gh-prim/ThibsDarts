import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../game_config.dart';
import '../lobby/lobby.dart';
import '../theme/tokens.dart';
import '../widgets/logo.dart';
import '../widgets/player_card.dart';
import '../widgets/stage.dart';
import '../widgets/status_indicator.dart';
import '../widgets/td_button.dart';
import 'mode_game_screen.dart';
import 'new_game_screen.dart';

/// Accueil : le Pi attend une partie.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    // Une partie lancée remplace le salon : elle ferme le salon à sa sortie.
    if (Lobby.instance.state == LobbyState.open) Lobby.instance.close();
    if (mounted) setState(() {}); // la dernière partie a pu changer
  }

  @override
  Widget build(BuildContext context) {
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
              const Row(
                children: [
                  Logo(height: 40),
                  Spacer(),
                  Row(
                    spacing: Td.s2,
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
