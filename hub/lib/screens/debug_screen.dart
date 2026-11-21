import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../cam/cam_link.dart';
import '../theme/tokens.dart';
import '../widgets/controls.dart';
import '../widgets/stage.dart';

/// Réglages > Mode Debug : actif partout (parties, entraînements). Le Pi 5 garde les photos de
/// chaque décision de la détection, et la vérité donnée sur le hub (correction, fantôme, fléchette
/// posée à la main) est rangée avec. Le mode reste actif après un redémarrage.
class DebugScreen extends StatelessWidget {
  const DebugScreen({super.key});

  static Color _color(String? kind) => switch (kind) {
    'flechette' => Td.succes,
    'SIGNALE' => Td.crepuscule,
    final String k when k.startsWith('verite') => Td.crepuscule,
    'ignore' || 'rien' || 'gros' => Td.fluo,
    'retrait' || 'tour' => Td.ciel,
    _ => Td.ink2,
  };

  static String _time(Object? ts) {
    if (ts is! num) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ts.toInt());
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final link = CamLink.instance;
    return Scaffold(
      backgroundColor: Td.beton,
      body: Stage(
        child: Padding(
          padding: const EdgeInsets.all(Td.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Td.s3,
            children: [
              Row(
                children: [
                  TdIconButton(
                    icon: LucideIcons.chevronLeft,
                    label: 'Retour',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: Td.s3),
                  const Icon(LucideIcons.bug, size: 28, color: Td.fluo),
                  const SizedBox(width: Td.s2),
                  Text('Mode Debug', style: TdText.inter(28, 34, 700, Td.ink)),
                ],
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: Td.s4,
                  children: [
                    SizedBox(
                      width: 360,
                      child: ValueListenableBuilder(
                        valueListenable: link.debugState,
                        builder: (context, state, _) {
                          final on = state?['on'] == true;
                          final projector = state?['projector'] != false;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            spacing: Td.s3,
                            children: [
                              Text('Debug', style: TdText.label),
                              TdSegmented(
                                options: const ['Actif', 'Arrêté'],
                                value: on ? 'Actif' : 'Arrêté',
                                touch: true,
                                onChanged: (v) => link.setDebug(on: v == 'Actif'),
                              ),
                              Text('Vidéoprojecteur', style: TdText.label),
                              TdSegmented(
                                options: const ['Allumé', 'Éteint'],
                                value: projector ? 'Allumé' : 'Éteint',
                                touch: true,
                                onChanged: (v) => link.setDebug(projector: v == 'Allumé'),
                              ),
                              if (state == null) Text('Pi 5 injoignable.', style: TdText.inter(15, 20, 600, Td.erreur)),
                              const Spacer(),
                              Text(
                                'Joue normalement (partie ou entraînement). Quand le hub se trompe :\n'
                                '- mauvais segment : Corriger, comme d\'habitude ;\n'
                                '- fléchette vue alors que rien n\'a été tiré : Corriger > Fantôme ;\n'
                                '- fléchette pas vue : pose-la à la main sur la cible du hub ;\n'
                                '- autre chose : bouton Signaler en bas à gauche, puis dis-le à Claude.',
                                style: TdText.caption,
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Td.verreLeger,
                          borderRadius: BorderRadius.circular(Td.rMd),
                          border: Border.all(color: Td.verreBord),
                        ),
                        padding: const EdgeInsets.all(Td.s3),
                        child: ValueListenableBuilder(
                          valueListenable: link.debugEvents,
                          builder: (context, events, _) {
                            if (events.isEmpty) {
                              return Center(child: Text('Aucune détection pour l\'instant.', style: TdText.body));
                            }
                            return ListView.separated(
                              itemCount: events.length,
                              separatorBuilder: (_, _) => const SizedBox(height: Td.s2),
                              itemBuilder: (context, i) {
                                final e = events[i];
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 84,
                                      child: Text(_time(e['ts']), style: TdText.inter(15, 20, 500, Td.ink3)),
                                    ),
                                    Container(
                                      width: 10,
                                      height: 10,
                                      margin: const EdgeInsets.only(top: 5, right: Td.s2),
                                      decoration: BoxDecoration(color: _color(e['kind'] as String?), shape: BoxShape.circle),
                                    ),
                                    Expanded(child: Text('${e['text'] ?? ''}', style: TdText.inter(16, 21, 500, Td.ink))),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pastille "Debug · Signaler", par-dessus tous les écrans tant que le mode Debug est actif.
class DebugBadge extends StatefulWidget {
  const DebugBadge({super.key});

  @override
  State<DebugBadge> createState() => _DebugBadgeState();
}

class _DebugBadgeState extends State<DebugBadge> {
  String? _flash;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _mark() {
    final ok = CamLink.instance.debugMark();
    _timer?.cancel();
    setState(() => _flash = ok ? 'Signalé' : 'Pi 5 injoignable');
    _timer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: CamLink.instance.debugState,
    builder: (context, state, _) {
      if (state?['on'] != true) return const SizedBox.shrink();
      return Pressable(
        onTap: _mark,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: Td.s3),
          decoration: BoxDecoration(
            color: const Color(0xE6121214),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _flash == null ? Td.fluo : Td.crepuscule, width: 2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: Td.s2,
            children: [
              Icon(_flash == null ? LucideIcons.bug : LucideIcons.flag, size: 18, color: _flash == null ? Td.fluo : Td.crepuscule),
              Text(
                _flash ?? 'Debug · Signaler',
                style: TdText.inter(15, 20, 700, _flash == null ? Td.fluo : Td.crepuscule),
              ),
            ],
          ),
        ),
      );
    },
  );
}
