import 'package:flutter/material.dart';

import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/tokens.dart';
import 'avatar.dart';

enum PlayerStatus { waiting, active, winner }

class PlayerSummary {
  const PlayerSummary(
    this.name, {
    this.average,
    this.score,
    this.status = PlayerStatus.waiting,
    this.message,
    this.ready = false,
  });
  final String name;

  /// Remplace la ligne du dessous ("Hôte", "Prêt"). Avec [ready], coche verte et bord vert.
  final String? message;
  final bool ready;

  /// Moyenne 3 fléchettes, null tant qu'il n'a pas tiré.
  final double? average;
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
    final avg = player.average;
    final msg = player.message;
    final sub = active
        ? (avg == null ? 'Au tir' : 'Au tir · ${formatAverage(avg)}')
        : (avg == null ? 'En attente' : 'moy. ${formatAverage(avg)}');
    return AnimatedContainer(
      duration: Td.rapide,
      padding: const EdgeInsets.all(Td.s3),
      decoration: BoxDecoration(
        color: active ? Td.verreMoyen : Td.verreLeger,
        borderRadius: BorderRadius.circular(Td.rLg),
        border: Border.all(color: active ? Td.fluo : (player.ready ? Td.succes : Td.verreBord)),
        boxShadow: active
            ? const [BoxShadow(color: Color(0x66FFE14D), blurRadius: 20, blurStyle: BlurStyle.outer)]
            : null,
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
                Text(
                  player.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TdText.inter(17, 22, 600, Td.ink),
                ),
                if (msg != null)
                  Row(
                    children: [
                      Icon(LucideIcons.check, size: 12, color: player.ready ? Td.succes : Td.ink2),
                      const SizedBox(width: Td.s1),
                      Text(msg, style: TdText.inter(13, 18, 400, player.ready ? Td.succes : Td.ink2)),
                    ],
                  )
                else
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
