import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../cam/cam_link.dart';
import '../theme/tokens.dart';
import '../widgets/controls.dart';
import '../widgets/stage.dart';
import '../widgets/td_button.dart';

/// Mode Debug : on tire librement, rien n'est compté. Le Pi 5 garde les photos de chaque décision
/// de la détection (fléchette comptée, tache ignorée, changement sans fléchette...) dans
/// /data/thibsdarts/debug, et "Signaler" garde les images du moment pour une fausse détection.
/// Le mode reste actif sur le Pi 5 après un redémarrage : l'accueil rouvre alors cet écran.
class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key});

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  final _link = CamLink.instance;
  String? _flash;

  @override
  void initState() {
    super.initState();
    _link
      ..onDart = _onDart
      ..onTakeout = _onTakeout
      ..setPlaying(true)
      ..setDebug(on: true);
  }

  @override
  void dispose() {
    if (_link.onDart == _onDart) {
      _link
        ..onDart = null
        ..onTakeout = null
        ..setPlaying(false);
    }
    super.dispose();
  }

  // Les fléchettes arrivent aussi en événements de debug : ici on ne compte rien.
  void _onDart(Object dart, Object? position, String? traceId) {}
  void _onTakeout() {}

  void _quit() {
    _link.setDebug(on: false);
    Navigator.of(context).pop();
  }

  void _mark() {
    final ok = _link.debugMark();
    setState(() => _flash = ok ? 'Signalé : images gardées sur le Pi 5.' : 'Pi 5 injoignable.');
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  static Color _color(String? kind) => switch (kind) {
    'flechette' => Td.succes,
    'SIGNALE' => Td.crepuscule,
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _quit();
      },
      child: Scaffold(
        backgroundColor: Td.betonNuit,
        body: Stage(
          child: Padding(
            padding: const EdgeInsets.all(Td.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Td.s3,
              children: [
                Row(
                  children: [
                    TdIconButton(icon: LucideIcons.chevronLeft, label: 'Quitter le debug', onPressed: _quit),
                    const SizedBox(width: Td.s3),
                    const Icon(LucideIcons.bug, size: 28, color: Td.fluo),
                    const SizedBox(width: Td.s2),
                    Text('Debug', style: TdText.inter(28, 34, 700, Td.ink)),
                    const SizedBox(width: Td.s4),
                    Expanded(
                      child: Text(
                        'Tire librement, rien n\'est compté. Chaque détection garde ses photos sur le Pi 5.',
                        style: TdText.caption,
                        maxLines: 2,
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: Td.s4,
                    children: [
                      SizedBox(width: 340, child: _controls()),
                      Expanded(child: _events()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _controls() {
    return ValueListenableBuilder(
      valueListenable: _link.debugState,
      builder: (context, state, _) {
        final on = state?['on'] == true;
        final projector = state?['projector'] != false;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Td.s3,
          children: [
            Text('Vidéoprojecteur', style: TdText.label),
            TdSegmented(
              options: const ['Allumé', 'Éteint'],
              value: projector ? 'Allumé' : 'Éteint',
              touch: true,
              onChanged: (v) => _link.setDebug(projector: v == 'Allumé'),
            ),
            Text(
              state == null
                  ? 'Pi 5 injoignable.'
                  : on
                  ? 'Captures actives.'
                  : 'Captures en cours d\'activation...',
              style: TdText.inter(15, 20, 600, state == null ? Td.erreur : on ? Td.succes : Td.ink2),
            ),
            const Spacer(),
            if (_flash != null) Text(_flash!, style: TdText.inter(15, 20, 600, Td.crepuscule)),
            TdButton(label: 'Signaler', icon: LucideIcons.flag, onPressed: _mark),
            Text(
              'Une fausse détection ou une fléchette ratée : appuie sur Signaler, puis dis-le à Claude.',
              style: TdText.caption,
            ),
          ],
        );
      },
    );
  }

  Widget _events() {
    return Container(
      decoration: BoxDecoration(
        color: Td.verreLeger,
        borderRadius: BorderRadius.circular(Td.rMd),
        border: Border.all(color: Td.verreBord),
      ),
      padding: const EdgeInsets.all(Td.s3),
      child: ValueListenableBuilder(
        valueListenable: _link.debugEvents,
        builder: (context, events, _) {
          if (events.isEmpty) {
            return Center(child: Text('Rien pour l\'instant. Tire une fléchette.', style: TdText.body));
          }
          return ListView.separated(
            itemCount: events.length,
            separatorBuilder: (_, _) => const SizedBox(height: Td.s2),
            itemBuilder: (context, i) {
              final e = events[i];
              final c = _color(e['kind'] as String?);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 84, child: Text(_time(e['ts']), style: TdText.inter(15, 20, 500, Td.ink3))),
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(top: 5, right: Td.s2),
                    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                  ),
                  Expanded(
                    child: Text('${e['text'] ?? ''}', style: TdText.inter(16, 21, i == 0 ? 700 : 500, Td.ink)),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
