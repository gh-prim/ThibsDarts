import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../widgets/logo.dart';
import '../widgets/player_card.dart';
import '../widgets/stage.dart';
import '../widgets/status_indicator.dart';
import '../widgets/td_button.dart';

/// Accueil : le Pi attend une partie.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  // Données de démo, en attendant SQLite.
  static const _lastPlayers = [
    PlayerSummary('Thibs', 62.4),
    PlayerSummary('Max', 48.1),
    PlayerSummary('Inès', 41.7),
  ];

  void _soon(BuildContext context, String what) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: Td.asphalteHaut,
      content: Text('$what arrive à la prochaine étape.', style: TdText.body.copyWith(color: Td.ink)),
    ));
  }

  @override
  Widget build(BuildContext context) {
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
                  Logo(),
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
                          Text("Le 501 t'attend.", style: TdText.title),
                          const SizedBox(height: Td.s4),
                          Text(
                            'Dernière partie : 501 double out, avec Max et Inès. Thibs a gagné en 18 fléchettes.',
                            style: TdText.body,
                          ),
                          const SizedBox(height: Td.s6),
                          TdButton(
                            label: 'Rejouer',
                            icon: Icons.refresh,
                            onPressed: () => _soon(context, 'La partie'),
                          ),
                          const SizedBox(height: Td.s4),
                          TdButton(
                            label: 'Nouvelle partie',
                            icon: Icons.add,
                            variant: TdButtonVariant.secondary,
                            onPressed: () => _soon(context, 'Le choix du mode'),
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
                          Text('Joueurs de la dernière partie', style: TdText.label),
                          for (final p in _lastPlayers) PlayerCard(player: p),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: Td.ink3),
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
