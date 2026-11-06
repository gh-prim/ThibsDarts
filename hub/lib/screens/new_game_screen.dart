import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../game_config.dart';
import '../theme/tokens.dart';
import '../widgets/controls.dart';
import '../widgets/stage.dart';
import '../widgets/td_button.dart';
import 'game_screen.dart';

/// "Choisis ton jeu" (planche NouvellePartie).
class NewGameScreen extends StatefulWidget {
  const NewGameScreen({super.key});

  @override
  State<NewGameScreen> createState() => _NewGameScreenState();
}

class _Mode {
  const _Mode(this.glyph, this.title, this.desc, {this.start});
  final String glyph, title, desc;
  final int? start;
}

const _modes = [
  _Mode('301', 'Le sprint', 'Double à la sortie.', start: 301),
  _Mode('501', 'Le classique', 'Double à la sortie.', start: 501),
  _Mode('15+', 'Cricket', 'Ferme, marque, chambre.'),
  _Mode('1>20', 'Around the clock', 'De 1 à 20, dans l’ordre.'),
  _Mode('S·D·T', 'Shanghai', 'S, D, T au même tour.'),
  _Mode('K', 'Killer', 'Trois vies. Pas d’amis.'),
  _Mode('½', 'Halve-it', 'Rate, ton score fond.'),
  _Mode('27', 'Bob’s 27', 'Doubles, pour souffrir.'),
  _Mode('T20', 'Entraînements', 'Solo, séries et routines.'),
];

class _NewGameScreenState extends State<NewGameScreen> {
  _Mode _mode = _modes[1];
  final List<String> _order = ['Thibs', 'Max', 'Inès'];
  final List<String> _guests = [];
  String _out = 'Double';
  int _legs = 2;

  void _toggle(String name) => setState(() => _order.contains(name) ? _order.remove(name) : _order.add(name));

  void _addGuest() {
    if (_order.length >= 8) return;
    final name = 'Invité ${_guests.length + 1}';
    setState(() {
      _guests.add(name);
      _order.add(name);
    });
  }

  void _pickMode(_Mode m) {
    if (m.start == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          backgroundColor: Td.asphalteHaut,
          duration: const Duration(seconds: 2),
          content: Text('${m.title} arrive bientôt. Pour l’instant : 301 ou 501.',
              style: TdText.inter(15, 20, 400, Td.ink)),
        ));
      return;
    }
    setState(() => _mode = m);
  }

  void _launch() {
    if (_order.isEmpty) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => GameScreen(
        config: GameConfig(
          players: List.of(_order),
          startScore: _mode.start!,
          doubleOut: _out == 'Double',
          legsToWin: _legs,
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final everyone = [...knownPlayers, ..._guests];
    return Scaffold(
      backgroundColor: Td.beton,
      body: Stage(
        child: Padding(
          padding: const EdgeInsets.all(Td.s4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 44,
                      child: Row(
                        children: [
                          TdIconButton(
                            icon: LucideIcons.chevronLeft,
                            label: 'Retour',
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          const SizedBox(width: Td.s3),
                          Text('Choisis ton jeu', style: TdText.inter(28, 34, 700, Td.ink).copyWith(letterSpacing: -0.3)),
                        ],
                      ),
                    ),
                    const SizedBox(height: Td.s3),
                    Expanded(
                      child: Column(
                        spacing: Td.s2,
                        children: [
                          for (var r = 0; r < 3; r++)
                            Expanded(
                              child: Row(
                                spacing: Td.s2,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final m in _modes.sublist(r * 3, r * 3 + 3))
                                    Expanded(
                                      child: ModeTile(
                                        glyph: m.glyph,
                                        title: m.title,
                                        desc: m.desc,
                                        selected: m == _mode,
                                        onTap: () => _pickMode(m),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Td.s4),
              Container(
                width: 336,
                padding: const EdgeInsets.all(Td.s4),
                decoration: BoxDecoration(
                  color: Td.verreLeger,
                  borderRadius: BorderRadius.circular(Td.rXl),
                  border: Border.all(color: Td.verreBord),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text("Joueurs, dans l'ordre", style: TdText.inter(13, 18, 600, Td.ink2)),
                    const SizedBox(height: Td.s3),
                    Wrap(
                      spacing: Td.s2,
                      runSpacing: Td.s2,
                      children: [
                        for (final n in everyone)
                          TdChip(
                            label: _order.contains(n) ? '${_order.indexOf(n) + 1}. $n' : n,
                            icon: LucideIcons.user,
                            selected: _order.contains(n),
                            onTap: () => _toggle(n),
                          ),
                        TdChip(label: 'Invité', icon: LucideIcons.plus, onTap: _addGuest),
                      ],
                    ),
                    const SizedBox(height: Td.s5),
                    Text('Sortie', style: TdText.inter(13, 18, 600, Td.ink2)),
                    const SizedBox(height: Td.s3),
                    TdSegmented(
                      options: const ['Double', 'Simple'],
                      value: _out,
                      touch: true,
                      onChanged: (v) => setState(() => _out = v),
                    ),
                    const SizedBox(height: Td.s5),
                    Text('Manches gagnantes', style: TdText.inter(13, 18, 600, Td.ink2)),
                    const SizedBox(height: Td.s3),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TdStepper(value: _legs, min: 1, max: 5, onChanged: (v) => setState(() => _legs = v)),
                    ),
                    const Spacer(),
                    TdButton(
                      label: 'Lancer',
                      icon: LucideIcons.play,
                      onPressed: _order.isEmpty ? null : _launch,
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
