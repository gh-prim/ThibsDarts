import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/tokens.dart';
import 'hit_tag.dart';
import 'td_button.dart';

enum CelebrationKind { win, oneEighty }

/// Une stat sous la victoire ("Meilleur tour", 140).
class CelebrationStat {
  const CelebrationStat(this.label, this.value);
  final String label;
  final String value;
}

/// Célébration plein écran (composant Celebration, planches Victoire et Fete180).
class Celebration extends StatefulWidget {
  const Celebration({
    super.key,
    required this.kind,
    required this.winner,
    this.tag,
    this.copy,
    this.stats = const [],
    this.onAgain,
    this.onHome,
    this.onTap,
  });

  final CelebrationKind kind;
  final String winner;

  /// Texte du tag à la place de "GAGNÉ" ("ÉGALITÉ", "FINI").
  final String? tag;

  /// Phrase à la place de "X plie la partie. Sans forcer."
  final String? copy;
  final List<CelebrationStat> stats;
  final VoidCallback? onAgain;
  final VoidCallback? onHome;

  /// 180 : toucher l'écran pour continuer.
  final VoidCallback? onTap;

  @override
  State<Celebration> createState() => _CelebrationState();
}

class _CelebrationState extends State<Celebration> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
    ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// td-up : apparaît en montant de 12 px, après [delay] ms, sur 280 ms.
  Widget _up(int delay, Widget child) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, c) {
        final t = Td.courbeSortie.transform(((_c.value * 1400 - delay) / 280).clamp(0.0, 1.0));
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - t)),
            child: Transform.scale(scale: 0.98 + 0.02 * t, child: c),
          ),
        );
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final win = widget.kind == CelebrationKind.win;
    final copy = widget.copy != null
        ? widget.copy!
        : win
        ? '${widget.winner} plie la partie. Sans forcer.'
        : 'Trois T20. ${widget.winner} a même pas transpiré.';
    final body = Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: Td.betonNuit)),
        const Positioned.fill(child: ColoredBox(color: Td.voile)),
        // td-fete__b2 : horizon golden hour
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, 1.36),
                radius: 1.1,
                colors: [Color(0x4DFF7A2F), Color(0x24FF4D8D), Color(0x00121214)],
                stops: [0, 0.45, 0.75],
              ),
            ),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(Td.s6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                win
                    ? HitTag(
                        kind: TagKind.triple,
                        text: widget.tag ?? 'GAGNÉ',
                        fontSize: widget.tag == null ? 112 : 96,
                      )
                    : const HitTag(kind: TagKind.oneEighty, text: '180', fontSize: 172),
                const SizedBox(height: Td.s4 + Td.s4),
                _up(700, Text(copy, style: TdText.inter(17, 22, 500, Td.ink), textAlign: TextAlign.center)),
                if (widget.stats.isNotEmpty) ...[
                  const SizedBox(height: Td.s4),
                  _up(
                    850,
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: Td.s6,
                      children: [
                        for (final s in widget.stats)
                          Column(
                            children: [
                              Text(s.value, style: TdText.rounded(28, 800, Td.ink, height: 32)),
                              Text(s.label, style: TdText.inter(13, 18, 400, Td.ink2)),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
                if (widget.onAgain != null || widget.onHome != null) ...[
                  const SizedBox(height: Td.s4),
                  _up(
                    1000,
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: Td.s3,
                      children: [
                        SizedBox(
                          width: 240,
                          child: TdButton(
                            label: 'Rejouer',
                            icon: LucideIcons.refreshCw,
                            height: Td.ciblePi,
                            onPressed: widget.onAgain,
                          ),
                        ),
                        SizedBox(
                          width: 240,
                          child: TdButton(
                            label: 'Accueil',
                            icon: LucideIcons.house,
                            variant: TdButtonVariant.secondary,
                            height: Td.ciblePi,
                            onPressed: widget.onHome,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (widget.onTap != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 20,
            child: Text(
              "Touche l'écran pour continuer.",
              textAlign: TextAlign.center,
              style: TdText.inter(13, 18, 400, Td.ink3),
            ),
          ),
      ],
    );
    return Semantics(
      label: 'Célébration',
      child: widget.onTap == null
          ? body
          : GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onTap, child: body),
    );
  }
}
