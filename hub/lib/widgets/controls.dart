import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/tokens.dart';

/// Petit effet d'appui commun (scale 0.97).
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.scale = 0.97});

  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 100),
        child: widget.child,
      ),
    );
  }
}

/// Bouton icône rond en verre (Button variant icon).
class TdIconButton extends StatelessWidget {
  const TdIconButton({super.key, required this.icon, required this.label, this.onPressed, this.size = 44});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return Semantics(
      button: true,
      label: label,
      child: Pressable(
        onTap: onPressed,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: disabled ? const Color(0x0DFFFFFF) : Td.verreMoyen,
            border: Border.all(color: disabled ? Colors.transparent : Td.verreBord),
          ),
          child: Icon(icon, size: size >= 96 ? 36 : 20, color: disabled ? Td.desactiveInk : Td.ink),
        ),
      ),
    );
  }
}

/// Puce (Chip).
class TdChip extends StatelessWidget {
  const TdChip({super.key, required this.label, this.icon, this.selected = false, this.onTap});

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Td.rapide,
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: Td.s3),
        decoration: BoxDecoration(
          color: selected ? Td.sunsetFond : Td.verreLeger,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? Td.sunset : Td.verreBord),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 16, color: Td.ink), const SizedBox(width: Td.s1)],
            Text(label, style: TdText.inter(15, 20, 500, Td.ink)),
          ],
        ),
      ),
    );
  }
}

/// Contrôle segmenté (SegmentedControl). [touch] = hauteur 72 pour le Pi.
class TdSegmented extends StatelessWidget {
  const TdSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.touch = false,
    this.height,
    this.disabled = const {},
  });

  final List<String> options;
  final String value;
  final ValueChanged<String> onChanged;
  final bool touch;
  final double? height;
  final Set<String> disabled;

  @override
  Widget build(BuildContext context) {
    final h = height ?? (touch ? Td.ciblePi : 36);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Td.verreLeger,
        borderRadius: BorderRadius.circular(Td.rMd),
        border: Border.all(color: Td.verreBord),
      ),
      child: Row(
        spacing: 2,
        children: [
          for (final o in options)
            Expanded(
              child: Pressable(
                onTap: disabled.contains(o) ? null : () => onChanged(o),
                child: AnimatedContainer(
                  duration: Td.rapide,
                  height: h,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: o == value ? Td.ink : Colors.transparent,
                    borderRadius: BorderRadius.circular(Td.rMd - 3),
                  ),
                  child: Text(
                    o,
                    style: TdText.inter(touch ? 22 : 15, touch ? 28 : 20, touch ? 700 : 600,
                        disabled.contains(o) ? Td.desactiveInk : (o == value ? Td.beton : Td.ink2)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Stepper tactile : - valeur +.
class TdStepper extends StatelessWidget {
  const TdStepper({super.key, required this.value, required this.onChanged, this.min = 1, this.max = 8});

  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: Td.s2,
      children: [
        TdIconButton(
          icon: LucideIcons.minus,
          label: 'Moins',
          size: Td.ciblePiFort,
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
        SizedBox(
          width: 94,
          child: Text('$value', textAlign: TextAlign.center, style: TdText.rounded(48, 800, Td.ink, height: 52)),
        ),
        TdIconButton(
          icon: LucideIcons.plus,
          label: 'Plus',
          size: Td.ciblePiFort,
          onPressed: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}

/// Tuile de mode de jeu (ModeTile).
class ModeTile extends StatelessWidget {
  const ModeTile({super.key, required this.glyph, required this.title, required this.desc, this.selected = false, this.onTap});

  final String glyph;
  final String title;
  final String desc;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Td.rapide,
        padding: const EdgeInsets.all(Td.s4),
        decoration: BoxDecoration(
          color: selected ? Td.sunsetFond : Td.verreMoyen,
          borderRadius: BorderRadius.circular(Td.rXl),
          border: Border.all(color: selected ? Td.sunset : Td.verreBord),
          boxShadow: const [BoxShadow(color: Color(0x73000000), blurRadius: 24, offset: Offset(0, 8), blurStyle: BlurStyle.outer)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(glyph,
                  style: TdText.rounded(48, 900, selected ? Td.sunset : Td.ink, height: 52).copyWith(letterSpacing: -1)),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TdText.inter(17, 22, 600, Td.ink)),
                Text(desc, maxLines: 1, overflow: TextOverflow.ellipsis, style: TdText.inter(13, 18, 400, Td.ink2)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
