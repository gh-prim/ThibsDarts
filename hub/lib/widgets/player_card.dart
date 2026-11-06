import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class PlayerSummary {
  const PlayerSummary(this.name, this.average);
  final String name;
  final double average;
}

/// Carte joueur compacte (avatar, nom, moyenne).
class PlayerCard extends StatelessWidget {
  const PlayerCard({super.key, required this.player, this.active = false});

  final PlayerSummary player;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: Td.ciblePi,
      padding: const EdgeInsets.symmetric(horizontal: Td.s4),
      decoration: BoxDecoration(
        color: Td.verreLeger,
        borderRadius: BorderRadius.circular(Td.rLg),
        border: Border.all(color: active ? Td.fluo : Td.bord, width: active ? 2 : 1),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: Td.asphalteHaut,
            child: Text(player.name.characters.first.toUpperCase(), style: TdText.headline),
          ),
          const SizedBox(width: Td.s3),
          Expanded(child: Text(player.name, style: TdText.headline)),
          Text(player.average.toStringAsFixed(1).replaceAll('.', ','), style: TdText.label),
        ],
      ),
    );
  }
}
