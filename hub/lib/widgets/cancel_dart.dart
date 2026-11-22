import 'dart:convert';
import 'dart:io';

import 'package:darts_engine/darts_engine.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../cam/cam_link.dart';
import '../cam/cam_traces.dart';
import '../setup/owner_store.dart';
import '../theme/tokens.dart';
import 'controls.dart';
import 'dartboard.dart';
import 'td_button.dart';

/// Fléchette retirée du tour (le joueur la relance) et la raison donnée.
class CancelDart {
  const CancelDart(this.index, {required this.ghost});
  final int index;

  /// Coup fantôme : vu par les caméras alors que rien n'a été tiré.
  final bool ghost;
}

/// Bouton "Annuler" des écrans de jeu.
class CancelDartButton extends StatelessWidget {
  const CancelDartButton({super.key, required this.onPressed, this.height = Td.ciblePi});

  final VoidCallback? onPressed;
  final double height;

  @override
  Widget build(BuildContext context) => TdButton(
    label: 'Annuler',
    icon: LucideIcons.undo2,
    variant: TdButtonVariant.secondary,
    height: height,
    onPressed: onPressed,
  );
}

/// Demande quelle fléchette annuler et pourquoi, puis envoie le rapport (Pi 5, journal).
/// Null si le joueur revient en arrière ou s'il n'y a rien à annuler.
Future<CancelDart?> askCancelDart(BuildContext context, List<DartThrow> turn, List<BoardHit> hits) async {
  if (turn.isEmpty) return null;
  final c = await showDialog<CancelDart>(
    context: context,
    barrierColor: const Color(0xCC000000),
    builder: (_) => _CancelDialog(turn: turn),
  );
  if (c == null) return null;
  final trace = c.index < hits.length ? hits[c.index].traceId : null;
  reportCancel(turn[c.index], ghost: c.ghost, traceId: trace);
  return c;
}

/// Rapport d'une annulation : Pi 5 (trace gardée, exemple sorti de l'apprentissage),
/// mode Debug, et journal local `annulations.jsonl` du dossier de données.
void reportCancel(DartThrow dart, {required bool ghost, String? traceId}) {
  final reason = ghost ? 'fantome' : 'annulation';
  if (traceId != null) CamTraces.cancel(traceId, reason);
  if (ghost) CamLink.instance.debugTruth('fantome', detected: dart, traceId: traceId);
  try {
    final f = File('${OwnerStore.instance.dir.path}/annulations.jsonl');
    f.writeAsStringSync(
      '${jsonEncode({
        'ts': DateTime.now().millisecondsSinceEpoch,
        'reason': reason,
        'dart': dart.isMiss ? 'MISS' : dart.label,
        'trace': ?traceId,
        'game': ?CamLink.instance.debugGame,
      })}\n',
      mode: FileMode.append,
    );
  } catch (_) {}
}

/// Impacts après avoir retiré la fléchette [index] : ceux qui restent gardent leur place, renumérotés.
List<BoardHit> hitsWithout(List<BoardHit> hits, int index, List<DartThrow> turn) {
  final rest = [...hits];
  if (index < rest.length) rest.removeAt(index);
  return [
    for (var i = 0; i < turn.length; i++)
      i < rest.length && rest[i].dart == turn[i]
          ? BoardHit(turn[i], rest[i].position, i + 1, traceId: rest[i].traceId)
          : BoardHit(turn[i], boardPositionFor(turn[i]), i + 1, traceId: i < rest.length ? rest[i].traceId : null),
  ];
}

class _CancelDialog extends StatefulWidget {
  const _CancelDialog({required this.turn});

  final List<DartThrow> turn;

  @override
  State<_CancelDialog> createState() => _CancelDialogState();
}

class _CancelDialogState extends State<_CancelDialog> {
  late int _index = widget.turn.length - 1;

  String _name(DartThrow d) => d.isMiss ? 'Raté' : d.label;

  @override
  Widget build(BuildContext context) {
    final options = [for (final (i, d) in widget.turn.indexed) '${i + 1} · ${_name(d)}'];
    return Dialog(
      backgroundColor: Td.plateauNoir,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Td.rXl)),
      child: Padding(
        padding: const EdgeInsets.all(Td.s8),
        child: SizedBox(
          width: 600,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Annuler une fléchette', style: TdText.headline),
              const SizedBox(height: Td.s4),
              if (options.length > 1) ...[
                TdSegmented(
                  options: options,
                  value: options[_index],
                  touch: true,
                  onChanged: (v) => setState(() => _index = options.indexOf(v)),
                ),
                const SizedBox(height: Td.s4),
              ] else ...[
                Text(options.single, style: TdText.rounded(28, 800, Td.ink, height: 32)),
                const SizedBox(height: Td.s4),
              ],
              Text('Raison', style: TdText.inter(13, 18, 500, Td.ink3)),
              const SizedBox(height: Td.s2),
              Row(
                spacing: Td.s3,
                children: [
                  Expanded(
                    child: TdButton(
                      label: 'Annulation',
                      icon: LucideIcons.undo2,
                      variant: TdButtonVariant.secondary,
                      onPressed: () => Navigator.of(context).pop(CancelDart(_index, ghost: false)),
                    ),
                  ),
                  Expanded(
                    child: TdButton(
                      label: 'Coup fantôme',
                      icon: LucideIcons.ghost,
                      onPressed: () => Navigator.of(context).pop(CancelDart(_index, ghost: true)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Td.s3),
              TdButton(
                label: 'Retour',
                variant: TdButtonVariant.secondary,
                height: 56,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
