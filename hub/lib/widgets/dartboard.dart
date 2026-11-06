import 'dart:math' as math;

import 'package:darts_engine/darts_engine.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Ordre des secteurs, en partant du haut, sens horaire.
const sectors = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5];

// Rayons du plateau (unités du design system, viewBox -205..205).
const _rB = 6.35, _rOb = 15.9, _rTi = 99.0, _rTo = 107.0, _rDi = 162.0, _rDo = 170.0;

/// Une fléchette posée sur le plateau.
class BoardHit {
  const BoardHit(this.dart, this.position, this.n);
  final DartThrow dart;

  /// Position en unités plateau (centre = 0,0).
  final Offset position;
  final int n;
}

/// Convertit une position (unités plateau) en fléchette.
DartThrow dartAt(Offset p) {
  final r = p.distance;
  if (r <= _rB) return DartThrow.bull;
  if (r <= _rOb) return DartThrow.outerBull;
  if (r > _rDo) return const DartThrow.miss();
  // Angle depuis le haut, sens horaire.
  var a = math.atan2(p.dx, -p.dy) * 180 / math.pi;
  if (a < 0) a += 360;
  final sector = sectors[((a + 9) ~/ 18) % 20];
  if (r >= _rTi && r <= _rTo) return DartThrow.triple(sector);
  if (r >= _rDi) return DartThrow.double(sector);
  return DartThrow.single(sector);
}

/// Position "type" d'une fléchette sur le plateau (comme dartXY du design system),
/// pour une fléchette saisie à la main.
Offset boardPositionFor(DartThrow d) {
  Offset polar(double r, double deg) {
    final a = (deg - 90) * math.pi / 180;
    return Offset(r * math.cos(a), r * math.sin(a));
  }

  if (d.isMiss) return polar(186, 9 * 18 + 6);
  if (d.sector == 25) return d.multiplier == 2 ? const Offset(1.5, -2) : const Offset(8, -8);
  final i = sectors.indexOf(d.sector);
  final r = switch (d.multiplier) { 3 => 103.0, 2 => 166.0, _ => 135.0 };
  return polar(r, i * 18.0 + 2);
}

/// Plateau virtuel (composant Dartboard) : segments touchés en couleur,
/// impacts numérotés, segment visé en bleu. Touchable pour le simulateur.
class Dartboard extends StatelessWidget {
  const Dartboard({super.key, this.hits = const [], this.aimed, this.dim = false, this.onTapBoard});

  final List<BoardHit> hits;
  final DartThrow? aimed;
  final bool dim;
  final ValueChanged<Offset>? onTapBoard;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(builder: (context, c) {
        final scale = c.maxWidth / 410;
        return GestureDetector(
          onTapUp: onTapBoard == null
              ? null
              : (d) => onTapBoard!((d.localPosition - Offset(c.maxWidth / 2, c.maxHeight / 2)) / scale),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: CustomPaint(painter: _BoardPainter(hits: hits, aimed: aimed, dim: dim))),
              for (final h in hits)
                Positioned(
                  left: c.maxWidth / 2 + h.position.dx * scale - 30,
                  top: c.maxHeight / 2 + h.position.dy * scale - 30,
                  width: 60,
                  height: 60,
                  child: _Impact(key: ValueKey('impact${h.n}${h.position}'), hit: h, scale: scale),
                ),
            ],
          ),
        );
      }),
    );
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter({required this.hits, required this.aimed, required this.dim});

  final List<BoardHit> hits;
  final DartThrow? aimed;
  final bool dim;

  static double _rad(double deg) => (deg - 90) * math.pi / 180;

  Path _seg(double r0, double r1, double a0, double a1) {
    final p = Path();
    p.arcTo(Rect.fromCircle(center: Offset.zero, radius: r1), _rad(a0), _rad(a1) - _rad(a0), true);
    p.arcTo(Rect.fromCircle(center: Offset.zero, radius: r0), _rad(a1), _rad(a0) - _rad(a1), false);
    p.close();
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 410;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(s);

    canvas.drawCircle(Offset.zero, 202, Paint()..color = Td.betonNuit);
    canvas.drawCircle(
        Offset.zero,
        202,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Td.verreBord
          ..strokeWidth = 1 / s);

    // Ce qui est touché : "20T", "20D", "20s" (simple extérieur), "B", "OB".
    final hitKeys = <String, int>{};
    for (final h in hits) {
      final d = h.dart;
      if (d.isMiss) continue;
      if (d.sector == 25) {
        hitKeys[d.multiplier == 2 ? 'B' : 'OB'] = d.multiplier;
      } else {
        hitKeys['${d.sector}${const ['s', 'D', 'T'][d.multiplier - 1]}'] = d.multiplier;
      }
    }
    final hitSectors = {for (final h in hits) if (!h.dart.isMiss && h.dart.sector != 25) h.dart.sector};

    final wire = Paint()
      ..style = PaintingStyle.stroke
      ..color = Td.plateauFil
      ..strokeWidth = 0.8;
    const rings = [('S', _rOb, _rTi), ('T', _rTi, _rTo), ('s', _rTo, _rDi), ('D', _rDi, _rDo)];
    const tripleShader = LinearGradient(colors: [Td.sunset, Td.crepuscule], begin: Alignment.topLeft, end: Alignment.bottomRight);

    for (var i = 0; i < 20; i++) {
      final sec = sectors[i];
      final a0 = i * 18.0 - 9, a1 = i * 18.0 + 9;
      final even = i % 2 == 0;
      for (final (r, r0, r1) in rings) {
        final path = _seg(r0, r1, a0, a1);
        final key = r == 'T' ? '${sec}T' : r == 'D' ? '${sec}D' : r == 's' ? '${sec}s' : null;
        final hit = key != null && hitKeys.containsKey(key);
        final isAim = aimed != null &&
            aimed!.sector == sec &&
            ((aimed!.multiplier == 3 && r == 'T') ||
                (aimed!.multiplier == 2 && r == 'D') ||
                (aimed!.multiplier == 1 && (r == 'S' || r == 's')));
        final paint = Paint();
        if (hit && r == 'T') {
          paint.shader = tripleShader.createShader(path.getBounds());
        } else {
          paint.color = hit
              ? (r == 'D' ? Td.fluo : Td.sunset)
              : isAim
                  ? Td.ciel
                  : (r == 'S' || r == 's')
                      ? (even ? Td.plateauNoir : Td.plateauCreme)
                      : (even ? Td.plateauRouge : Td.plateauVert);
          if (dim && !hit && !isAim) paint.color = paint.color.withValues(alpha: 0.55);
        }
        canvas.drawPath(path, paint);
        canvas.drawPath(path, isAim ? (Paint()
          ..style = PaintingStyle.stroke
          ..color = Td.ciel
          ..strokeWidth = 0.8) : wire);
      }
    }

    // Bull
    Color bullC(String k, Color base) => hitKeys.containsKey(k) ? Td.crepuscule : (dim ? base.withValues(alpha: 0.55) : base);
    canvas.drawCircle(Offset.zero, _rOb, Paint()..color = bullC('OB', Td.plateauVert));
    canvas.drawCircle(Offset.zero, _rOb, wire);
    canvas.drawCircle(Offset.zero, _rB, Paint()..color = bullC('B', Td.plateauRouge));
    canvas.drawCircle(Offset.zero, _rB, wire);

    // Numéros
    for (var i = 0; i < 20; i++) {
      final sec = sectors[i];
      final on = hitSectors.contains(sec);
      final aim = aimed?.sector == sec;
      final tp = TextPainter(
        text: TextSpan(
          text: '$sec',
          style: TdText.rounded(on ? 21 : 18, 800, on ? Td.sunset : (aim ? Td.ciel : Td.plateauNumero), height: on ? 21 : 18),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final a = _rad(i * 18.0);
      final c = Offset(186 * math.cos(a), 186 * math.sin(a));
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BoardPainter old) => old.hits != hits || old.aimed != aimed || old.dim != dim;
}

/// Impact numéroté (td-impact) : apparaît en zoomant, avec une onde.
class _Impact extends StatelessWidget {
  const _Impact({super.key, required this.hit, required this.scale});

  final BoardHit hit;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final r = 8 * scale;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1100),
      builder: (_, t, _) {
        final pop = const Cubic(0.34, 1.56, 0.64, 1).transform((t * 1100 / 480).clamp(0, 1));
        final pulse = const Cubic(0.2, 0.8, 0.2, 1).transform(t);
        return Stack(
          alignment: Alignment.center,
          children: [
            // Onde
            Opacity(
              opacity: 1 - pulse,
              child: Container(
                width: 2 * 7 * scale * (0.4 + 2 * pulse),
                height: 2 * 7 * scale * (0.4 + 2 * pulse),
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Td.ink, width: 1.5)),
              ),
            ),
            Opacity(
              opacity: pop.clamp(0, 1),
              child: Transform.scale(
                scale: 2.4 - 1.4 * pop,
                child: Container(
                  width: 2 * r + 4,
                  height: 2 * r + 4,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hit.dart.isMiss ? Td.erreur : Td.ink,
                    border: Border.all(color: Td.beton, width: 2),
                  ),
                  child: Text('${hit.n}', style: TdText.rounded(10 * scale, 900, Td.beton, height: 10 * scale)),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
