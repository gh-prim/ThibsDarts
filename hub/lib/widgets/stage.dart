import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// Fond béton de nuit, avec option "horizon" (lueur coucher de soleil en bas).
class Stage extends StatelessWidget {
  const Stage({super.key, required this.child, this.horizon = true});

  final Widget child;
  final bool horizon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Td.beton),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: horizon
              ? const RadialGradient(
                  center: Alignment(0, 1.36),
                  radius: 1.1,
                  colors: [Color(0x4DFF7A2F), Color(0x24FF4D8D), Color(0x00121214)],
                  stops: [0, 0.45, 0.75],
                )
              : null,
        ),
        child: child,
      ),
    );
  }
}

/// Panneau en verre (Liquid Glass). Sans flou pour tenir 30 fps sur le Pi.
class GlassPanel extends StatelessWidget {
  const GlassPanel({super.key, required this.child, this.padding = const EdgeInsets.all(Td.s4), this.radius = Td.rLg});

  final Widget child;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Td.verreMoyen,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Td.verreBord),
      ),
      child: child,
    );
  }
}
