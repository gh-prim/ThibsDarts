import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../cam/cam_traces.dart';
import '../theme/tokens.dart';
import '../widgets/controls.dart';
import '../widgets/dartboard.dart';
import '../widgets/stage.dart';

/// Couleur de chaque caméra, la même que dans l'overlay dessiné par le Pi 5 (cam/vision/traces.py).
const camColors = {
  'Bas': Color(0xFF28C8FF),
  'Haut gauche': Color(0xFFFF50C8),
  'Haut droite': Color(0xFF50DC50),
};
const _otherColor = Color(0xFFB4B4B4);
const _cible = 'Cible';

Color camColor(String cam) => camColors[cam] ?? _otherColor;

/// Ce que les caméras ont capté pour une fléchette : un onglet par caméra (image du Pi 5 avec
/// l'overlay, et les valeurs mesurées), et un onglet Cible avec le point de chaque caméra.
/// Que des faits, pas d'interprétation.
class TraceScreen extends StatefulWidget {
  const TraceScreen({super.key, required this.traceId});

  final String traceId;

  @override
  State<TraceScreen> createState() => _TraceScreenState();
}

class _TraceScreenState extends State<TraceScreen> {
  Map<String, dynamic>? _trace;
  Map<String, dynamic>? _learning;
  bool _loading = true;
  String _tab = _cible;
  bool _overlay = true;
  bool _zoom = false;
  bool _after = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([CamTraces.trace(widget.traceId), CamTraces.learning()]);
    if (!mounted) return;
    setState(() {
      _trace = results[0];
      _learning = results[1];
      _loading = false;
      final cams = _cams;
      if (cams.isNotEmpty) _tab = cams.first;
    });
  }

  Map<String, dynamic> get _camData => (_trace?['cams'] as Map?)?.cast<String, dynamic>() ?? const {};

  /// Caméras dans l'ordre habituel, puis les autres.
  List<String> get _cams {
    final names = _camData.keys.toList();
    return [
      for (final n in camColors.keys)
        if (names.contains(n)) n,
      for (final n in names)
        if (!camColors.containsKey(n)) n,
    ];
  }

  static String _mm(Object? v) => v is num ? v.toStringAsFixed(1).replaceAll('.', ',') : '-';

  @override
  Widget build(BuildContext context) {
    final t = _trace;
    return Scaffold(
      backgroundColor: Td.betonNuit,
      body: Stage(
        child: Padding(
          padding: const EdgeInsets.all(Td.s3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Td.s3,
            children: [
              Row(
                children: [
                  Text('Caméras', style: TdText.inter(22, 28, 700, Td.ink)),
                  const SizedBox(width: Td.s4),
                  if (t != null)
                    Text(
                      'Retenu : ${t['segment']} · x ${_mm(t['x'])} · y ${_mm(t['y'])} mm',
                      style: TdText.inter(15, 20, 500, Td.ink2),
                    ),
                  const Spacer(),
                  TdIconButton(icon: LucideIcons.x, label: 'Fermer', onPressed: () => Navigator.of(context).pop()),
                ],
              ),
              if (_loading)
                const Expanded(child: Center(child: CircularProgressIndicator(color: Td.sunset)))
              else if (t == null)
                Expanded(
                  child: Center(
                    child: Text(
                      'Trace introuvable sur le Pi 5 (il garde les 30 dernières fléchettes).',
                      style: TdText.inter(17, 22, 500, Td.ink2),
                    ),
                  ),
                )
              else ...[
                TdSegmented(
                  options: [..._cams, _cible],
                  value: _tab,
                  touch: true,
                  height: 48,
                  onChanged: (v) => setState(() => _tab = v),
                ),
                Expanded(child: _tab == _cible ? _board(t) : _camera(_tab)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // MARK: une caméra

  Widget _camera(String cam) {
    final c = (_camData[cam] as Map?)?.cast<String, dynamic>() ?? const {};
    final seen = c['seen'] == true;
    final url = CamTraces.imageUrl(widget.traceId, cam, after: _after, overlay: _overlay, zoom: _zoom);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Td.rMd),
                child: Container(
                  color: Colors.black,
                  child: url == null
                      ? null
                      : Image.network(
                          url,
                          key: ValueKey(url),
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                          errorBuilder: (_, _, _) => Center(
                            child: Text('Image indisponible', style: TdText.inter(15, 20, 500, Td.ink3)),
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: Td.s3),
        SizedBox(
          width: 250,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Td.s2,
            children: [
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(color: camColor(cam), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: Td.s2),
                  Text(cam, style: TdText.inter(17, 22, 700, Td.ink)),
                ],
              ),
              if (seen) ...[
                _fact('Segment', '${c['segment']}', big: true),
                _fact('Pointe', 'x ${_mm((c['tip'] as List?)?[0])} · y ${_mm((c['tip'] as List?)?[1])} mm'),
                _fact('Tache', '${c['area']} px'),
                _fact('Longueur', '${_mm(c['length'])} px'),
              ] else ...[
                _fact('Segment', 'Rien vu', big: true),
                if (c['why'] != null) _fact('Refus', '${c['why']}'),
              ],
              _fact('Changement', '${_mm(((c['change'] as num?) ?? 0) * 100)} %'),
              const Spacer(),
              TdSegmented(
                options: const ['Avant', 'Après'],
                value: _after ? 'Après' : 'Avant',
                height: 40,
                onChanged: (v) => setState(() => _after = v == 'Après'),
              ),
              TdSegmented(
                options: const ['Overlay', 'Brut'],
                value: _overlay ? 'Overlay' : 'Brut',
                height: 40,
                onChanged: (v) => setState(() => _overlay = v == 'Overlay'),
              ),
              TdSegmented(
                options: const ['Entière', 'Zoom'],
                value: _zoom ? 'Zoom' : 'Entière',
                height: 40,
                onChanged: (v) => setState(() => _zoom = v == 'Zoom'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _fact(String label, String value, {bool big = false}) => Row(
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      SizedBox(width: 96, child: Text(label, style: TdText.inter(13, 18, 500, Td.ink3))),
      Expanded(
        child: Text(
          value,
          style: big ? TdText.rounded(26, 800, Td.ink, height: 30) : TdText.inter(15, 20, 600, Td.ink),
        ),
      ),
    ],
  );

  // MARK: la cible

  Widget _board(Map<String, dynamic> t) {
    final raw = (t['raw'] as List?)?.cast<num>();
    final adjusted = raw != null && ((raw[0] - (t['x'] as num)).abs() > 0.05 || (raw[1] - (t['y'] as num)).abs() > 0.05);
    final lcams = ((_learning?['cams'] as Map?) ?? const {}).cast<String, dynamic>();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Center(
            child: Stack(
              children: [
                const Dartboard(dim: true),
                Positioned.fill(
                  child: IgnorePointer(child: CustomPaint(painter: _TracePainter(t, _cams))),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: Td.s3),
        SizedBox(
          width: 330,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Td.s2,
            children: [
              for (final cam in _cams) _camRow(cam),
              _legendRow(
                Td.ink,
                'Retenu',
                '${t['segment']}',
                'x ${_mm(t['x'])} · y ${_mm(t['y'])}',
              ),
              if (adjusted) _legendRow(Td.ink3, 'Sans ajustement', '', 'x ${_mm(raw[0])} · y ${_mm(raw[1])}'),
              const Spacer(),
              if (lcams.isNotEmpty) ...[
                Text('Corrections apprises', style: TdText.inter(13, 18, 600, Td.ink2)),
                for (final cam in _cams)
                  if (lcams[cam] is Map) _learnRow(cam, (lcams[cam] as Map).cast<String, dynamic>()),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _camRow(String cam) {
    final c = (_camData[cam] as Map?)?.cast<String, dynamic>() ?? const {};
    if (c['seen'] != true) return _legendRow(camColor(cam), cam, 'Rien vu', '');
    final tip = (c['tip'] as List?) ?? const [];
    return _legendRow(
      camColor(cam),
      cam,
      '${c['segment']}',
      tip.length == 2 ? 'x ${_mm(tip[0])} · y ${_mm(tip[1])}' : '',
    );
  }

  Widget _legendRow(Color color, String name, String seg, String xy) => Container(
    padding: const EdgeInsets.symmetric(horizontal: Td.s3, vertical: Td.s2),
    decoration: BoxDecoration(
      color: Td.verreLeger,
      borderRadius: BorderRadius.circular(Td.rSm),
      border: Border.all(color: Td.verreBord),
    ),
    child: Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: Td.s2),
        Expanded(child: Text(name, style: TdText.inter(15, 20, 600, Td.ink))),
        Text(seg, style: TdText.rounded(18, 800, Td.ink)),
        const SizedBox(width: Td.s2),
        SizedBox(
          width: 104,
          child: Text(xy, textAlign: TextAlign.right, style: TdText.inter(12, 16, 500, Td.ink3)),
        ),
      ],
    ),
  );

  Widget _learnRow(String cam, Map<String, dynamic> l) {
    final med = l['median_mm'];
    final parts = [
      '${l['corrections']} corr.',
      if (med != null) 'écart méd. ${_mm(med)} mm',
      'poids ${(l['weight'] as num?)?.toStringAsFixed(2) ?? '1.00'}',
      if ((l['zones'] as num? ?? 0) > 0) '${l['zones']} zone(s) ajustée(s)',
    ];
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: camColor(cam), shape: BoxShape.circle)),
        const SizedBox(width: Td.s2),
        Expanded(
          child: Text(
            parts.join(' · '),
            style: TdText.inter(12, 16, 500, l['recalibrate'] == true ? Td.sunset : Td.ink3),
          ),
        ),
      ],
    );
  }
}

/// Axe et pointe de chaque caméra sur la cible, et le point retenu (unités plateau = mm).
class _TracePainter extends CustomPainter {
  _TracePainter(this.trace, this.cams);

  final Map<String, dynamic> trace;
  final List<String> cams;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 410;
    final c = Offset(size.width / 2, size.height / 2);
    Offset at(num x, num y) => c + Offset(x.toDouble(), y.toDouble()) * s;
    final data = (trace['cams'] as Map).cast<String, dynamic>();
    for (final cam in cams) {
      final o = (data[cam] as Map).cast<String, dynamic>();
      if (o['seen'] != true) continue;
      final tip = (o['tip'] as List).cast<num>();
      final color = camColor(cam);
      final dir = (o['dir'] as List?)?.cast<num>();
      if (dir != null) {
        final line = Paint()
          ..color = color.withValues(alpha: 0.85)
          ..strokeWidth = 2;
        canvas.drawLine(
          at(tip[0] - dir[0] * 90, tip[1] - dir[1] * 90),
          at(tip[0] + dir[0] * 90, tip[1] + dir[1] * 90),
          line,
        );
      }
      canvas.drawCircle(at(tip[0], tip[1]), 6, Paint()..color = color);
      canvas.drawCircle(
        at(tip[0], tip[1]),
        6,
        Paint()
          ..color = Colors.black
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
    final p = at(trace['x'] as num, trace['y'] as num);
    final white = Paint()
      ..color = Td.ink
      ..strokeWidth = 3;
    canvas.drawLine(p - const Offset(10, 0), p + const Offset(10, 0), white);
    canvas.drawLine(p - const Offset(0, 10), p + const Offset(0, 10), white);
  }

  @override
  bool shouldRepaint(_TracePainter old) => old.trace != trace;
}
