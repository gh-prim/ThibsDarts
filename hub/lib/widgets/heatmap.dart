import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

// Heatmap des fléchettes : densité lissée (noyau gaussien) des positions réelles,
// en dégradé vert, jaune, orange, rouge. Unités plateau (centre 0,0, y vers le bas, double à 170).

/// Demi-côté de la zone couverte (comme le cadre du plateau, viewBox -205..205).
const heatHalf = 205.0;

/// Densité de [points] sur une grille [n] x [n] couvrant -205..205, de 0 à 1 (1 = zone la plus touchée).
/// [sigma] : rayon du lissage, en mm.
List<double> heatGrid(List<Offset> points, {int n = 96, double sigma = 11}) {
  final g = List<double>.filled(n * n, 0);
  if (points.isEmpty) return g;
  final cell = heatHalf * 2 / n, reach = (sigma * 3 / cell).ceil(), k = -1 / (2 * sigma * sigma);
  for (final p in points) {
    final cx = ((p.dx + heatHalf) / cell).floor(), cy = ((p.dy + heatHalf) / cell).floor();
    for (var y = math.max(0, cy - reach); y <= math.min(n - 1, cy + reach); y++) {
      final dy = (y + .5) * cell - heatHalf - p.dy;
      for (var x = math.max(0, cx - reach); x <= math.min(n - 1, cx + reach); x++) {
        final dx = (x + .5) * cell - heatHalf - p.dx;
        g[y * n + x] += math.exp((dx * dx + dy * dy) * k);
      }
    }
  }
  final top = g.reduce(math.max);
  if (top > 0) {
    for (var i = 0; i < g.length; i++) {
      g[i] /= top;
    }
  }
  return g;
}

const _stops = [Td.succes, Td.fluo, Td.sunset, Color(0xFFFF2D2D)];

/// Couleur d'une densité (0 à 1) : vert, jaune, orange, rouge. Bord fondu jusqu'à 2 %.
Color heatColor(double v) {
  if (v < .02) return const Color(0x00000000);
  final t = v.clamp(0.0, 1.0) * (_stops.length - 1), i = math.min(_stops.length - 2, t.floor());
  final c = Color.lerp(_stops[i], _stops[i + 1], t - i)!;
  return c.withValues(alpha: math.min(1, (v - .02) * 2.5));
}

/// Barre de légende : du vert (peu) au rouge (beaucoup).
const heatLegend = LinearGradient(colors: _stops);

/// Calque heatmap posé sur un plateau carré (même cadre que [Dartboard]).
class HeatLayer extends StatefulWidget {
  const HeatLayer({super.key, required this.points});

  final List<Offset> points;

  @override
  State<HeatLayer> createState() => _HeatLayerState();
}

class _HeatLayerState extends State<HeatLayer> {
  static const _n = 96;
  ui.Image? _img;
  int _version = 0;

  @override
  void initState() {
    super.initState();
    _build();
  }

  @override
  void didUpdateWidget(HeatLayer old) {
    super.didUpdateWidget(old);
    if (!_samePoints(old.points, widget.points)) _build();
  }

  static bool _samePoints(List<Offset> a, List<Offset> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _build() {
    final v = ++_version;
    final grid = heatGrid(widget.points, n: _n);
    final px = Uint8List(_n * _n * 4);
    for (var i = 0; i < grid.length; i++) {
      final c = heatColor(grid[i]);
      // Pixels prémultipliés : bords doux une fois l'image agrandie.
      final a = c.a;
      px[i * 4] = (c.r * a * 255).round();
      px[i * 4 + 1] = (c.g * a * 255).round();
      px[i * 4 + 2] = (c.b * a * 255).round();
      px[i * 4 + 3] = (a * 255).round();
    }
    ui.decodeImageFromPixels(px, _n, _n, ui.PixelFormat.rgba8888, (img) {
      if (!mounted || v != _version) {
        img.dispose();
        return;
      }
      setState(() {
        _img?.dispose();
        _img = img;
      });
    });
  }

  @override
  void dispose() {
    _img?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _HeatPainter(_img));
}

class _HeatPainter extends CustomPainter {
  _HeatPainter(this.img);
  final ui.Image? img;

  @override
  void paint(Canvas canvas, Size size) {
    final i = img;
    if (i == null) return;
    final s = size.width / 410, c = Offset(size.width / 2, size.height / 2);
    final dst = Rect.fromCenter(center: c, width: heatHalf * 2 * s, height: heatHalf * 2 * s);
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: 202 * s)));
    canvas.drawImageRect(
      i,
      Rect.fromLTWH(0, 0, i.width.toDouble(), i.height.toDouble()),
      dst,
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HeatPainter old) => old.img != img;
}
