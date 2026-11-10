import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../cam/cam_pairing.dart';
import '../theme/tokens.dart';

/// Opération en plusieurs étapes (appairage, changement de Wi-Fi) : les étapes, une barre qui avance
/// et bouge tant que ça tourne, la phrase du moment.
class StepsProgress extends StatelessWidget {
  const StepsProgress({super.key, required this.steps, required this.progress});

  final List<String> steps;
  final PairProgress progress;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final failed = p.state == PairState.failed;
    final done = p.state == PairState.done;
    final running = p.state == PairState.running;
    // Étapes finies, plus une demi-étape pour celle en cours.
    final value = done ? 1.0 : (p.step + (running ? 0.5 : 0)) / steps.length;
    final color = failed ? Td.erreur : (done ? Td.succes : Td.sunset);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Td.s2,
      children: [
        Row(
          children: [
            for (var i = 0; i < steps.length; i++)
              Expanded(
                child: _PairStep(label: steps[i], index: i, progress: p),
              ),
          ],
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Td.verreLeger),
                TweenAnimationBuilder<double>(
                  tween: Tween(end: value),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: v,
                    child: ColoredBox(color: color),
                  ),
                ),
                // Reflet qui défile tant que l'étape tourne : on voit que ça bouge.
                if (running)
                  const LinearProgressIndicator(
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation(Color(0x66FFFFFF)),
                  ),
              ],
            ),
          ),
        ),
        Text(
          p.detail,
          style: TdText.body.copyWith(color: failed ? Td.erreur : (done ? Td.succes : Td.ink2)),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _PairStep extends StatelessWidget {
  const _PairStep({required this.label, required this.index, required this.progress});

  final String label;
  final int index;
  final PairProgress progress;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final passed = index < p.step || (index == p.step && p.state == PairState.done);
    final current = index == p.step && p.state != PairState.done;
    final Widget mark;
    Color tint;
    if (passed) {
      tint = Td.succes;
      mark = const Icon(LucideIcons.circleCheck, size: 20, color: Td.succes);
    } else if (current && p.state == PairState.failed) {
      tint = Td.erreur;
      mark = const Icon(LucideIcons.circleX, size: 20, color: Td.erreur);
    } else if (current) {
      tint = Td.sunset;
      mark = const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2.5, color: Td.sunset),
      );
    } else {
      tint = Td.ink3;
      mark = const Icon(LucideIcons.circle, size: 20, color: Td.ink3);
    }
    return Row(
      spacing: Td.s2,
      children: [
        mark,
        Flexible(
          child: Text(
            label,
            style: TdText.caption.copyWith(color: tint),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
