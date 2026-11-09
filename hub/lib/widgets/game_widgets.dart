import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/tokens.dart';
import 'td_button.dart';

/// Gros score (composant ScoreDisplay, taille l).
enum ScoreState { normal, out, bust }

class ScoreDisplay extends StatelessWidget {
  const ScoreDisplay({
    super.key,
    required this.value,
    required this.label,
    this.sub,
    this.state = ScoreState.normal,
    this.size = 140,
    this.text,
  });

  /// Texte à la place de [value] ("7/9"), réduit pour tenir dans la largeur.
  final String? text;

  /// 140 (l), 88 (m) ou 48 (s).
  final double size;
  final int value;
  final String label;
  final String? sub;
  final ScoreState state;

  @override
  Widget build(BuildContext context) {
    Widget v = Text(
      text ?? '$value',
      maxLines: 1,
      style: TdText.rounded(
        size,
        size >= 140 ? 900 : 800,
        state == ScoreState.bust ? Td.erreur : Td.ink,
        height: size >= 140 ? 132 : (size >= 88 ? 88 : 52),
      ).copyWith(letterSpacing: size >= 140 ? -4 : (size >= 88 ? -2 : 0)),
    );
    if (state == ScoreState.out) {
      v = ShaderMask(blendMode: BlendMode.srcIn, shaderCallback: (r) => Td.goldenHour.createShader(r), child: v);
    }
    if (text != null) v = FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: v);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TdText.inter(13, 18, 600, Td.ink2)),
        const SizedBox(height: Td.s1),
        v,
        if (sub != null) ...[
          const SizedBox(height: Td.s1),
          Text(
            sub!,
            style: TdText.inter(
              15,
              20,
              state == ScoreState.bust ? 600 : 400,
              state == ScoreState.bust ? Td.erreur : Td.ink2,
            ),
          ),
        ],
      ],
    );
  }
}

/// Tuile chiffre clé (composant KpiTile) : libellé, valeur, unité. En verre avec [glass].
class KpiTile extends StatelessWidget {
  const KpiTile({super.key, required this.label, required this.value, this.unit, this.glass = true});

  final String label;
  final String value;
  final String? unit;
  final bool glass;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Td.s4, vertical: Td.s3),
      decoration: BoxDecoration(
        color: glass ? Td.verreMoyen : Td.asphalte,
        borderRadius: BorderRadius.circular(Td.rLg),
        border: Border.all(color: glass ? Td.verreBord : Td.bord),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TdText.inter(13, 18, 600, Td.ink2)),
          const SizedBox(height: Td.s1),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: TdText.rounded(40, 900, Td.ink, height: 44)),
              if (unit != null) ...[
                const SizedBox(width: Td.s2),
                Text(unit!, style: TdText.inter(15, 20, 400, Td.ink2)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Une case de fléchette (composant DartSlots).
enum SlotState { empty, current, hit, miss, error }

class SlotData {
  const SlotData(this.state, {this.label, this.value, this.highlight = false});
  final SlotState state;
  final String? label;
  final int? value;
  final bool highlight;
}

class DartSlots extends StatelessWidget {
  const DartSlots({super.key, required this.slots, this.height = Td.ciblePi});

  final List<SlotData> slots;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: Td.s2,
      children: [
        for (var i = 0; i < 3; i++)
          Expanded(
            child: _Slot(index: i, data: slots[i], height: height),
          ),
      ],
    );
  }
}

class _Slot extends StatelessWidget {
  const _Slot({required this.index, required this.data, required this.height});

  final int index;
  final SlotData data;
  final double height;

  @override
  Widget build(BuildContext context) {
    final big = data.state == SlotState.hit && data.highlight;
    final (Color? bg, Gradient? grad, Color border, double bw) = switch (data.state) {
      SlotState.empty => (null, null, Td.bordControle, 1.0),
      SlotState.current => (null, null, Td.fluo, 2.0),
      SlotState.error => (Td.erreurFond, null, Td.erreur, 1.0),
      _ when big => (null, Td.goldenHour, Colors.transparent, 1.0),
      _ => (Td.verreLeger, null, Td.verreBord, 1.0),
    };
    final shadow = switch (data.state) {
      SlotState.current => const [BoxShadow(color: Color(0x66FFE14D), blurRadius: 20, blurStyle: BlurStyle.outer)],
      _ when big => const [BoxShadow(color: Color(0x73FF7A2F), blurRadius: 32)],
      _ => null,
    };
    final Widget content = switch (data.state) {
      SlotState.empty => Text(
        '${index + 1}',
        style: TdText.rounded(36, 900, Td.ink3.withValues(alpha: 0.5), height: 38),
      ),
      SlotState.current => const Icon(LucideIcons.crosshair, size: 36, color: Td.fluo),
      SlotState.miss => _two('Raté', '0', Td.erreur, Td.ink2),
      SlotState.error => _two(data.label ?? '?', '${data.value ?? 0}', Td.erreur, Td.erreur),
      SlotState.hit => _two(data.label!, '${data.value}', big ? Td.onAccent : Td.ink, big ? Td.onAccent : Td.ink2),
    };
    final box = Container(
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        gradient: grad,
        borderRadius: BorderRadius.circular(Td.rMd),
        border: data.state == SlotState.empty ? null : Border.all(color: border, width: bw),
        boxShadow: shadow,
      ),
      child: content,
    );
    final framed = data.state == SlotState.empty ? CustomPaint(painter: _DashedBorder(), child: box) : box;
    if (data.state != SlotState.hit && data.state != SlotState.miss) return framed;
    // Animation "td-land" : la case rebondit quand la fléchette arrive.
    return TweenAnimationBuilder<double>(
      key: ValueKey('${data.label}$index'),
      tween: Tween(begin: 1.25, end: 1),
      duration: Td.lente,
      curve: const Cubic(0.34, 1.56, 0.64, 1),
      builder: (_, s, child) => Transform.scale(scale: s, child: child),
      child: framed,
    );
  }

  Widget _two(String l, String v, Color lc, Color vc) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l, style: TdText.rounded(l.length > 4 ? 26 : 36, 900, lc, height: 38)),
        Text(v, style: TdText.inter(15, 18, 500, vc)),
      ],
    ),
  );
}

class _DashedBorder extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(Td.rMd)).deflate(0.5);
    final path = Path()..addRRect(rr);
    final paint = Paint()
      ..color = Td.bordControle
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final m in path.computeMetrics()) {
      for (double d = 0; d < m.length; d += 7) {
        canvas.drawPath(m.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder oldDelegate) => false;
}

/// Suggestion de sortie (composant CheckoutHint).
class CheckoutHint extends StatelessWidget {
  const CheckoutHint({super.key, required this.route, this.label = 'Sortie'});

  final List<String> route;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: Td.s3, vertical: Td.s2),
      decoration: BoxDecoration(
        color: Td.verreLeger,
        borderRadius: BorderRadius.circular(Td.rMd),
        border: Border.all(color: Td.verreBord),
      ),
      child: Row(
        children: [
          Text(label, style: TdText.inter(13, 16, 600, Td.ink2)),
          const Spacer(),
          for (var i = 0; i < route.length; i++) ...[
            if (i > 0) const SizedBox(width: Td.s2),
            Container(
              constraints: const BoxConstraints(minWidth: 56),
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: Td.s2),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: i == route.length - 1 ? null : Td.verreMoyen,
                gradient: i == route.length - 1 ? Td.goldenHour : null,
                borderRadius: BorderRadius.circular(Td.rSm),
              ),
              child: Text(route[i], style: TdText.rounded(22, 800, i == route.length - 1 ? Td.onAccent : Td.ink)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Bannière (composant Banner).
class TdBanner extends StatelessWidget {
  const TdBanner({super.key, required this.text, this.error = true, this.alert = false});

  final String text;
  final bool error;

  /// Ton "alerte" : fond jaune fluo, triangle.
  final bool alert;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: Td.s4, vertical: Td.s3),
      decoration: BoxDecoration(
        color: alert ? const Color(0x24FFE14D) : (error ? Td.erreurFond : Td.infoFond),
        borderRadius: BorderRadius.circular(Td.rMd),
      ),
      child: Row(
        children: [
          Icon(
            alert ? LucideIcons.triangleAlert : (error ? LucideIcons.circleAlert : LucideIcons.info),
            size: 20,
            color: alert ? Td.fluo : (error ? Td.erreur : Td.ciel),
          ),
          const SizedBox(width: Td.s3),
          Expanded(child: Text(text, style: TdText.inter(15, 20, 400, Td.ink))),
        ],
      ),
    );
  }
}

/// Toast d'info (composant Toast).
class TdToast extends StatelessWidget {
  const TdToast({super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Td.s4, vertical: Td.s3),
      decoration: BoxDecoration(
        color: Td.verreFort,
        borderRadius: BorderRadius.circular(Td.rLg),
        border: Border.all(color: Td.verreBord),
        boxShadow: const [BoxShadow(color: Color(0x73000000), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.info, size: 22, color: Td.ciel),
          const SizedBox(width: Td.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: TdText.inter(15, 20, 600, Td.ink)),
                Text(body, style: TdText.inter(13, 18, 400, Td.ink2)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Confirmation d'une action qui efface quelque chose : true si confirmée.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierColor: const Color(0xCC000000),
    builder: (ctx) => Dialog(
      backgroundColor: Td.plateauNoir,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Td.rXl)),
      child: Padding(
        padding: const EdgeInsets.all(Td.s8),
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: TdText.headline),
              const SizedBox(height: Td.s2),
              Text(body, style: TdText.body),
              const SizedBox(height: Td.s6),
              Row(
                spacing: Td.s3,
                children: [
                  Expanded(
                    child: TdButton(
                      label: 'Continuer',
                      variant: TdButtonVariant.secondary,
                      onPressed: () => Navigator.of(ctx).pop(false),
                    ),
                  ),
                  Expanded(
                    child: TdButton(label: action, icon: LucideIcons.x, onPressed: () => Navigator.of(ctx).pop(true)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return ok == true;
}

/// Bouton "Arrêter" de l'écran de jeu : demande confirmation puis revient à l'accueil.
class StopGameButton extends StatelessWidget {
  const StopGameButton({super.key, this.size = 44});

  final double size;

  static Future<void> confirm(BuildContext context) async {
    final stop = await confirmAction(
      context,
      title: 'Arrêter la partie ?',
      body: 'Elle ne comptera pas dans l’historique.',
      action: 'Arrêter',
    );
    if (stop && context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Arrêter la partie',
    child: GestureDetector(
      onTap: () => confirm(context),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Td.rMd),
          border: Border.all(color: Td.plateauFil),
        ),
        child: Icon(LucideIcons.x, size: size * 0.5, color: Td.ink2),
      ),
    ),
  );
}
