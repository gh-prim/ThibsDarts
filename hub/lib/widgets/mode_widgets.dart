import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/tokens.dart';

/// Une colonne de joueur pour le tableau Cricket.
class CricketColumn {
  const CricketColumn(this.name, this.marks, this.score);
  final String name;

  /// 7 valeurs : 20, 19, 18, 17, 16, 15, bull.
  final List<int> marks;
  final int score;
}

/// Tableau Cricket (composant CricketBoard) : marques par joueur, numéros au milieu, points en bas.
class CricketBoard extends StatelessWidget {
  const CricketBoard({super.key, required this.players, required this.active});

  final List<CricketColumn> players;
  final int active;

  static const _rows = ['20', '19', '18', '17', '16', '15', 'Bull'];

  @override
  Widget build(BuildContext context) {
    final mid = (players.length / 2).ceil();
    Widget cell(int i, Widget child, {bool on = false, BorderRadius? r}) => Expanded(
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: on ? Td.verreMoyen : Td.verreLeger, borderRadius: r),
        child: child,
      ),
    );
    List<Widget> row(List<Widget> cols, Widget middle) {
      final out = [...cols];
      out.insert(players.length > 1 ? mid : out.length, middle);
      return out;
    }

    return Column(
      spacing: Td.s1,
      children: [
        Row(
          children: row([
            for (var i = 0; i < players.length; i++)
              Expanded(
                child: Text(
                  players[i].name,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TdText.inter(15, 20, 600, i == active ? Td.fluo : Td.ink2),
                ),
              ),
          ], const SizedBox(width: 72)),
        ),
        for (var r = 0; r < _rows.length; r++)
          Opacity(
            opacity: players.every((p) => p.marks[r] >= 3) ? 0.38 : 1,
            child: Row(
              children: row(
                [
                  for (var i = 0; i < players.length; i++)
                    cell(
                      i,
                      CustomPaint(size: const Size(30, 30), painter: _MarkPainter(players[i].marks[r])),
                      on: i == active,
                      r: BorderRadius.horizontal(
                        left: Radius.circular(i == 0 ? 6 : 0),
                        right: Radius.circular(i == players.length - 1 ? 6 : 0),
                      ),
                    ),
                ],
                Container(
                  width: 72,
                  height: 40,
                  alignment: Alignment.center,
                  color: Td.verreMoyen,
                  child: Text(
                    _rows[r],
                    style: TdText.rounded(
                      _rows[r] == 'Bull' ? 20 : 26,
                      900,
                      Td.ink,
                    ).copyWith(decoration: players.every((p) => p.marks[r] >= 3) ? TextDecoration.lineThrough : null),
                  ),
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: Td.s1),
          child: Row(
            children: row(
              [
                for (final p in players)
                  Expanded(
                    child: Text('${p.score}', textAlign: TextAlign.center, style: TdText.rounded(28, 800, Td.ink)),
                  ),
              ],
              SizedBox(
                width: 72,
                child: Text('pts', textAlign: TextAlign.center, style: TdText.inter(12, 16, 600, Td.ink3)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Marque cricket : /, X, puis X cerclé quand c'est fermé.
class _MarkPainter extends CustomPainter {
  _MarkPainter(this.n);
  final int n;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 32;
    canvas.scale(s);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..color = n >= 3 ? Td.sunset : Td.ink;
    if (n >= 1 && n < 3) canvas.drawLine(const Offset(8, 24), const Offset(24, 8), p);
    if (n == 2) canvas.drawLine(const Offset(8, 8), const Offset(24, 24), p);
    if (n >= 3) {
      canvas.drawCircle(const Offset(16, 16), 12, p);
      canvas.drawLine(const Offset(8.5, 23.5), const Offset(23.5, 8.5), p);
      canvas.drawLine(const Offset(8.5, 8.5), const Offset(23.5, 23.5), p);
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.n != n;
}

enum BadgeTone { succes, alerte, sunset }

/// Petit badge (composant Badge).
class TdBadge extends StatelessWidget {
  const TdBadge({super.key, required this.label, this.tone = BadgeTone.succes, this.icon});

  final String label;
  final BadgeTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (fond, ink) = switch (tone) {
      BadgeTone.succes => (Td.succesFond, Td.succes),
      BadgeTone.alerte => (const Color(0x24FFE14D), Td.fluo),
      BadgeTone.sunset => (Td.sunsetFond, Td.sunset),
    };
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: Td.s1,
        children: [
          if (icon != null) Icon(icon, size: 14, color: ink),
          Text(label, style: TdText.inter(13, 18, 600, ink)),
        ],
      ),
    );
  }
}

/// Icône "flamme" du badge Killer.
const killerIcon = LucideIcons.flame;
