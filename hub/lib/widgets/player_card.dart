import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'avatar.dart';

enum PlayerStatus { waiting, active, winner }

class PlayerSummary {
  const PlayerSummary(this.name, this.average, {this.score, this.status = PlayerStatus.waiting});
  final String name;
  final double average;
  final int? score;
  final PlayerStatus status;
}

String formatAverage(double a) => a.toStringAsFixed(1).replaceAll('.', ',');

/// Carte joueur (composant PlayerCard) : avatar, nom, "Au tir · moy." et score.
class PlayerCard extends StatelessWidget {
  const PlayerCard({super.key, required this.player});

  final PlayerSummary player;

  @override
  Widget build(BuildContext context) {
    final active = player.status == PlayerStatus.active;
    final sub = active ? 'Au tir · ${formatAverage(player.average)}' : 'moy. ${formatAverage(player.average)}';
    return AnimatedContainer(
      duration: Td.rapide,
      padding: const EdgeInsets.all(Td.s3),
      decoration: BoxDecoration(
        color: active ? Td.verreMoyen : Td.verreLeger,
        borderRadius: BorderRadius.circular(Td.rLg),
        border: Border.all(color: active ? Td.fluo : Td.verreBord),
        boxShadow: active ? const [BoxShadow(color: Color(0x66FFE14D), blurRadius: 20, blurStyle: BlurStyle.outer)] : null,
      ),
      child: Row(
        children: [
          Avatar(name: player.name, active: active),
          const SizedBox(width: Td.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(player.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TdText.inter(17, 22, 600, Td.ink)),
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TdText.inter(13, 18, 400, Td.ink2)),
              ],
            ),
          ),
          if (player.score != null)
            Text('${player.score}', style: TdText.rounded(32, 800, active ? Td.ink : Td.ink2, height: 36)),
        ],
      ),
    );
  }
}
