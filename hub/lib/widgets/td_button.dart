import 'package:flutter/material.dart';

import '../theme/tokens.dart';

enum TdButtonVariant { primary, secondary }

/// Gros bouton tactile : primaire (dégradé Golden Hour) ou secondaire (verre).
class TdButton extends StatefulWidget {
  const TdButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = TdButtonVariant.primary,
    this.height = Td.ciblePiFort,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final TdButtonVariant variant;
  final double height;

  @override
  State<TdButton> createState() => _TdButtonState();
}

class _TdButtonState extends State<TdButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final primary = widget.variant == TdButtonVariant.primary;
    final fg = primary ? Td.onAccent : Td.ink;
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: Td.rapide,
        curve: Td.courbeSortie,
        child: Container(
          height: widget.height,
          padding: const EdgeInsets.symmetric(horizontal: Td.s4),
          decoration: BoxDecoration(
            gradient: primary
                ? Td.goldenHour
                : const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x21FFFFFF), Color(0x17FFFFFF)],
                    stops: [0, 0.08],
                  ),
            borderRadius: BorderRadius.circular(Td.rXl),
            border: primary ? null : Border.all(color: Td.verreBord),
            // Arête de verre (inset 0 1px 0 blanc 22%) simulée par un léger dégradé.
            boxShadow: primary
                ? const [BoxShadow(color: Color(0x73FF7A2F), blurRadius: 32)]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, color: fg, size: 26),
                const SizedBox(width: Td.s2),
              ],
              Text(widget.label, style: TdText.button.copyWith(color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}
