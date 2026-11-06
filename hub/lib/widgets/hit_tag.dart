import 'dart:math' as math;

import 'package:darts_engine/darts_engine.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';

enum TagKind { simple, double, triple, bull, miss, checkout, oneEighty }

/// Tag bombé (composant HitTag) : "TRIPLE 20" en Permanent Marker,
/// révélé de gauche à droite comme un coup de bombe, avec halo et coulures.
class HitTag extends StatefulWidget {
  const HitTag({super.key, required this.kind, required this.text, this.fontSize});

  factory HitTag.forDart(DartThrow d, {Key? key, double? fontSize}) {
    final kind = d.isMiss
        ? TagKind.miss
        : d.sector == 25
            ? TagKind.bull
            : const [TagKind.simple, TagKind.double, TagKind.triple][d.multiplier - 1];
    final text = switch (kind) {
      TagKind.miss => 'À CÔTÉ',
      TagKind.bull => d.multiplier == 2 ? 'BULL' : 'OUTER BULL',
      _ => d.callout,
    };
    return HitTag(key: key, kind: kind, text: text, fontSize: fontSize);
  }

  final TagKind kind;
  final String text;

  /// Taille imposée (sur le Pi : 72 pour les touches, 48 pour hors cible).
  final double? fontSize;

  @override
  State<HitTag> createState() => _HitTagState();
}

class _HitTagState extends State<HitTag> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
    ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  (double, Gradient, Color, double, List<(double, double, double)>) get _style => switch (widget.kind) {
        TagKind.triple => (88, Td.goldenHour, Td.sunset, -5, const [(0.14, 0.5, 0.25), (0.52, 0.32, 0.4), (0.82, 0.62, 0.15)]),
        TagKind.checkout => (88, Td.goldenHour, Td.sunset, -5, const [(0.2, 0.5, 0.2), (0.76, 0.42, 0.35)]),
        TagKind.oneEighty => (172, Td.goldenHour, Td.crepuscule, -5, const [(0.16, 0.3, 0.15), (0.74, 0.38, 0.25)]),
        TagKind.double => (64, const LinearGradient(colors: [Td.fluo, Td.fluo]), Td.fluo, -5, const [(0.3, 0.34, 0.1)]),
        TagKind.bull => (96, const LinearGradient(colors: [Td.crepuscule, Td.sunset]), Td.crepuscule, -5, const [(0.25, 0.44, 0.2), (0.7, 0.3, 0.5)]),
        TagKind.simple => (56, const LinearGradient(colors: [Td.ink, Td.ink]), Td.ink, -5, const []),
        TagKind.miss => (44, const LinearGradient(colors: [Td.ink3, Td.ink3]), Td.ink3, 3, const []),
      };

  @override
  Widget build(BuildContext context) {
    final (defaultSize, fill, c1, deg, drips) = _style;
    final size = widget.fontSize ?? defaultSize;
    final base = TextStyle(fontFamily: 'PermanentMarker', fontSize: size, height: 1, letterSpacing: size * 0.01);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final ms = _c.value * 1800;
        // td-bombe : 900 ms, révélation sur 55 %, scale 1.14 -> 1.
        final b = const Cubic(0.1, 0.9, 0.2, 1).transform((ms / 900).clamp(0, 1));
        final reveal = (b / 0.55).clamp(0.0, 1.0);
        final scale = b < 0.55 ? 1.14 - 0.10 * (b / 0.55) : 1.04 - 0.04 * ((b - 0.55) / 0.45);
        final spray = const Cubic(0.2, 0.8, 0.2, 1).transform((ms / 900).clamp(0, 1));
        return Transform.rotate(
          angle: deg * math.pi / 180,
          child: Padding(
            padding: EdgeInsets.fromLTRB(size * 0.2, size * 0.12, size * 0.2, size * 0.3),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Halo de bombe
                Positioned(
                  left: -size, right: -size, top: -size * 0.4, bottom: -size * 0.4,
                  child: Opacity(
                    opacity: 0.7 - 0.44 * spray,
                    child: Transform.scale(
                      scale: 0.6 + 0.4 * spray,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(colors: [c1, c1.withValues(alpha: 0)]),
                        ),
                      ),
                    ),
                  ),
                ),
                // Coulures (td-tag__drips) : partent à 66 % de la hauteur du texte.
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (_, box) => Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (final (x, h, d) in drips)
                          Positioned(
                            left: box.maxWidth * x,
                            top: box.maxHeight * 0.66,
                            child: Container(
                              width: size * 0.05,
                              height: size * h * const Cubic(0.45, 0.05, 0.55, 0.95)
                                  .transform(((ms - (d + 0.35) * 1000) / 1200).clamp(0, 1)),
                              decoration: BoxDecoration(
                                color: c1,
                                borderRadius: BorderRadius.vertical(bottom: Radius.circular(size * 0.05)),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Transform.scale(
                  scale: scale,
                  child: ClipRect(
                    clipper: _RevealClipper(reveal),
                    child: Stack(
                      children: [
                        // Contour sombre (td-tag__under)
                        Text(widget.text,
                            style: base.copyWith(
                              foreground: Paint()
                                ..style = PaintingStyle.stroke
                                ..strokeWidth = size * 0.18
                                ..strokeJoin = StrokeJoin.round
                                ..color = Td.beton,
                            )),
                        ShaderMask(
                          blendMode: BlendMode.srcIn,
                          shaderCallback: (r) => fill.createShader(r),
                          child: Text(widget.text, style: base.copyWith(color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RevealClipper extends CustomClipper<Rect> {
  _RevealClipper(this.t);
  final double t;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(-size.width * 0.05, -size.height * 0.2, size.width * (t * 1.1 - 0.05), size.height * 2.2);

  @override
  bool shouldReclip(_RevealClipper old) => old.t != t;
}
