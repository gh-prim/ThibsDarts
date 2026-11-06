import 'dart:ui' show ImageFilter;

import 'package:darts_engine/darts_engine.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/tokens.dart';
import '../widgets/controls.dart';
import '../widgets/dartboard.dart';
import '../widgets/stage.dart';

/// Résultat d'une correction : quelle fléchette, et sa nouvelle valeur.
class Correction {
  const Correction(this.index, this.dart);
  final int index;
  final DartThrow dart;
}

/// "Corriger une fléchette" (planche Correction) : plateau à gauche,
/// pavé de correction à droite. Renvoie une [Correction] ou null.
class CorrectionScreen extends StatefulWidget {
  const CorrectionScreen({super.key, required this.turn, required this.hits});

  final List<DartThrow> turn;
  final List<BoardHit> hits;

  @override
  State<CorrectionScreen> createState() => _CorrectionScreenState();
}

const _mults = ['Simple', 'Double', 'Triple'];

class _CorrectionScreenState extends State<CorrectionScreen> {
  late int _index = widget.turn.isEmpty ? 0 : widget.turn.length - 1;
  late String _mult;
  late int _sector; // 0 = raté, 25 = bull

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final d = _index < widget.turn.length ? widget.turn[_index] : const DartThrow.triple(20);
    _sector = d.sector;
    _mult = _mults[d.isMiss ? 0 : d.multiplier - 1];
  }

  DartThrow get _dart {
    if (_sector == 0) return const DartThrow.miss();
    if (_sector == 25) return DartThrow(25, _mult == 'Double' ? 2 : 1);
    return DartThrow(_sector, _mults.indexOf(_mult) + 1);
  }

  String get _label => switch (_dart) {
        DartThrow(isMiss: true) => 'Raté',
        DartThrow(sector: 25, multiplier: 2) => 'Bull',
        DartThrow(sector: 25) => 'Outer bull',
        final d => d.label,
      };

  void _pickOnBoard(Offset p) {
    final d = dartAt(p);
    setState(() {
      _sector = d.sector;
      if (!d.isMiss) _mult = _mults[d.multiplier - 1];
    });
  }

  @override
  Widget build(BuildContext context) {
    final options = [for (var i = 0; i < 3; i++) 'Fléchette ${i + 1}'];
    final disabledDarts = {for (var i = widget.turn.length + 1; i < 3; i++) options[i]};
    final isBull = _sector == 25;
    return Scaffold(
      backgroundColor: Td.betonNuit,
      body: Stage(
        child: Padding(
          padding: const EdgeInsets.all(Td.s3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460, maxHeight: 520),
                      child: Dartboard(
                        hits: widget.hits,
                        aimed: _sector == 0 ? null : _dart,
                        onTapBoard: _pickOnBoard,
                      ),
                    ),
                    const SizedBox(height: Td.s2),
                    Text('Ou touche directement le secteur sur la cible.', style: TdText.inter(15, 20, 400, Td.ink2)),
                  ],
                ),
              ),
              const SizedBox(width: Td.s3),
              ClipRRect(
                borderRadius: BorderRadius.circular(Td.rXl),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    width: 520,
                    padding: const EdgeInsets.all(Td.s5),
                    decoration: BoxDecoration(
                      color: Td.verreFort,
                      borderRadius: BorderRadius.circular(Td.rXl),
                      border: Border.all(color: Td.verreBord),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: Td.s3,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text('Corriger une fléchette', style: TdText.inter(22, 28, 700, Td.ink))),
                            TdIconButton(icon: LucideIcons.x, label: 'Fermer', onPressed: () => Navigator.of(context).pop()),
                          ],
                        ),
                        TdSegmented(
                          options: options,
                          value: options[_index],
                          touch: true,
                          disabled: disabledDarts,
                          onChanged: (v) => setState(() {
                            _index = options.indexOf(v);
                            _load();
                          }),
                        ),
                        // Aperçu + multiplicateur (td-pad__a)
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Fléchette ${_index + 1} corrigée', style: TdText.inter(12, 16, 500, Td.ink3)),
                                  Text('$_label · ${_dart.score}', style: TdText.rounded(28, 800, Td.ink, height: 32)),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 270,
                              child: TdSegmented(
                                options: _mults,
                                value: _mult,
                                height: 44,
                                disabled: isBull ? const {'Triple'} : const {},
                                onChanged: (v) => setState(() => _mult = v),
                              ),
                            ),
                          ],
                        ),
                        // Pavé 1 à 20 + 25 (td-pad__g, 7 colonnes)
                        for (var r = 0; r < 3; r++)
                          Row(
                            spacing: Td.s2,
                            children: [
                              for (var c = 0; c < 7; c++)
                                Expanded(child: _key(r * 7 + c + 1 == 21 ? 25 : r * 7 + c + 1)),
                            ],
                          ),
                        const Spacer(),
                        Row(
                          spacing: Td.s2,
                          children: [
                            Expanded(
                              flex: 10,
                              child: _ActionButton(
                                label: 'Raté',
                                icon: LucideIcons.x,
                                onTap: () => setState(() => _sector = 0),
                              ),
                            ),
                            _ActionButton(label: 'Annuler', tertiary: true, onTap: () => Navigator.of(context).pop()),
                            Expanded(
                              flex: 14,
                              child: _ActionButton(
                                label: 'Valider',
                                primary: true,
                                onTap: () => Navigator.of(context).pop(Correction(_index, _dart)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _key(int n) {
    final on = _sector == n;
    return Pressable(
      scale: 0.94,
      onTap: () => setState(() {
        _sector = n;
        if (n == 25 && _mult == 'Triple') _mult = 'Simple';
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? Td.ink : Td.verreMoyen,
          borderRadius: BorderRadius.circular(Td.rSm),
          border: Border.all(color: on ? Td.ink : Td.verreBord),
        ),
        child: Text('$n', style: TdText.rounded(24, 800, on ? Td.beton : Td.ink)),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, this.icon, this.onTap, this.primary = false, this.tertiary = false});

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool primary;
  final bool tertiary;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? Td.onAccent : tertiary ? Td.sunset : Td.ink;
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: Td.s4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: primary ? Td.goldenHour : null,
          color: primary || tertiary ? null : Td.verreMoyen,
          borderRadius: BorderRadius.circular(Td.rMd),
          border: primary || tertiary ? null : Border.all(color: Td.verreBord),
          boxShadow: primary ? const [BoxShadow(color: Color(0x73FF7A2F), blurRadius: 32)] : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 20, color: fg), const SizedBox(width: Td.s2)],
            Text(label, style: TdText.inter(17, 22, 600, fg)),
          ],
        ),
      ),
    );
  }
}
