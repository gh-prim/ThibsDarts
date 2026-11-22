import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../system/sounds.dart';
import '../theme/tokens.dart';
import 'controls.dart';

IconData _icon(int volume, bool muted) {
  if (muted || volume == 0) return LucideIcons.volumeX;
  if (volume < 50) return LucideIcons.volume1;
  return LucideIcons.volume2;
}

/// Haut-parleur rond dans l'en-tête des écrans. Un appui ouvre le réglage du volume.
class VolumeButton extends StatelessWidget {
  const VolumeButton({super.key, this.size = 44});

  final double size;

  static void open(BuildContext context) {
    showDialog<void>(context: context, barrierColor: const Color(0xCC000000), builder: (_) => const VolumeSheet());
  }

  @override
  Widget build(BuildContext context) {
    Sounds.load();
    return ListenableBuilder(
      listenable: Listenable.merge([Sounds.volume, Sounds.muted]),
      builder: (context, _) {
        final off = Sounds.muted.value || Sounds.volume.value == 0;
        return Semantics(
          button: true,
          label: 'Volume',
          child: Pressable(
            onTap: () => open(context),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: Td.plateauNoir,
                shape: BoxShape.circle,
                border: Border.all(color: off ? Td.erreur : Td.plateauFil),
              ),
              child: Icon(_icon(Sounds.volume.value, Sounds.muted.value), size: 20, color: off ? Td.erreur : Td.ink2),
            ),
          ),
        );
      },
    );
  }
}

/// Fenêtre du volume : muet, moins, curseur, plus.
class VolumeSheet extends StatelessWidget {
  const VolumeSheet({super.key});

  static const _step = 10;

  void _set(int v, {bool preview = false}) {
    Sounds.setVolume(v);
    if (preview) Sounds.play('t20');
  }

  @override
  Widget build(BuildContext context) {
    Sounds.load();
    return Dialog(
      backgroundColor: Td.plateauNoir,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Td.rXl)),
      child: Padding(
        padding: const EdgeInsets.all(Td.s6),
        child: SizedBox(
          width: 620,
          child: ListenableBuilder(
            listenable: Listenable.merge([Sounds.volume, Sounds.muted]),
            builder: (context, _) {
              final v = Sounds.volume.value;
              final muted = Sounds.muted.value;
              final off = muted || v == 0;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Td.s5,
                children: [
                  Row(
                    children: [
                      Text('Volume', style: TdText.headline),
                      const Spacer(),
                      Text(muted ? 'Muet' : '$v %', style: TdText.rounded(34, 900, off ? Td.erreur : Td.ink)),
                      const SizedBox(width: Td.s4),
                      TdIconButton(icon: LucideIcons.x, label: 'Fermer', onPressed: () => Navigator.of(context).pop()),
                    ],
                  ),
                  Row(
                    spacing: Td.s3,
                    children: [
                      _MuteButton(muted: muted, onTap: () => Sounds.setMuted(!muted)),
                      _RoundButton(
                        icon: LucideIcons.minus,
                        label: 'Moins fort',
                        onTap: v > 0 ? () => _set(((v - 1) ~/ _step) * _step, preview: true) : null,
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 12,
                            activeTrackColor: muted ? Td.desactiveInk : Td.sunset,
                            inactiveTrackColor: Td.plateauFil,
                            thumbColor: muted ? Td.ink3 : Td.ink,
                            overlayColor: Td.sunsetFond,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 18),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 36),
                            trackShape: const RoundedRectSliderTrackShape(),
                          ),
                          child: Slider(
                            value: v.toDouble(),
                            max: 100,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            onChanged: (x) => _set(x.round()),
                            onChangeEnd: (x) => _set(x.round(), preview: true),
                          ),
                        ),
                      ),
                      _RoundButton(
                        icon: LucideIcons.plus,
                        label: 'Plus fort',
                        onTap: v < 100 || muted ? () => _set((v ~/ _step + 1) * _step, preview: true) : null,
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MuteButton extends StatelessWidget {
  const _MuteButton({required this.muted, required this.onTap});

  final bool muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    toggled: muted,
    label: 'Muet',
    child: Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Td.rapide,
        width: Td.ciblePi,
        height: Td.ciblePi,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: muted ? Td.erreurFond : null,
          border: Border.all(color: muted ? Td.erreur : Td.plateauFil, width: muted ? 2 : 1),
        ),
        child: Icon(muted ? LucideIcons.volumeX : LucideIcons.volume2, size: 30, color: muted ? Td.erreur : Td.ink),
      ),
    ),
  );
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: Pressable(
      onTap: onTap,
      child: Container(
        width: Td.ciblePi,
        height: Td.ciblePi,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Td.plateauFil),
        ),
        child: Icon(icon, size: 28, color: onTap == null ? Td.ink3 : Td.ink),
      ),
    ),
  );
}
