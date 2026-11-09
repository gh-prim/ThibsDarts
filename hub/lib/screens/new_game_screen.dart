import 'package:darts_engine/darts_engine.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../game_config.dart';
import '../players/player_store.dart';
import '../theme/tokens.dart';
import '../widgets/controls.dart';
import '../widgets/stage.dart';
import '../widgets/td_button.dart';
import 'mode_game_screen.dart';
import 'salon_screen.dart';

/// "Choisis ton jeu" (planche NouvellePartie).
class NewGameScreen extends StatefulWidget {
  const NewGameScreen({super.key});

  @override
  State<NewGameScreen> createState() => _NewGameScreenState();
}

class _Mode {
  const _Mode(this.glyph, this.title, this.desc, {this.start, this.mode, this.training = false});
  final String glyph, title, desc;
  final int? start;
  final GameMode? mode;

  /// Série libre en solo (planche Entraînement).
  final bool training;

  bool get playable => start != null || mode != null || training;
}

const _modes = [
  _Mode('301', 'Le sprint', 'Double à la sortie.', start: 301),
  _Mode('501', 'Le classique', 'Double à la sortie.', start: 501),
  _Mode('15+', 'Cricket', 'Ferme, marque, chambre.', mode: GameMode.cricket),
  _Mode('1>20', 'Around the clock', 'De 1 à 20, dans l’ordre.', mode: GameMode.clock),
  _Mode('S·D·T', 'Shanghai', 'S, D, T au même tour.', mode: GameMode.shanghai),
  _Mode('K', 'Killer', 'Trois vies. Pas d’amis.', mode: GameMode.killer),
  _Mode('½', 'Halve-it', 'Rate, ton score fond.', mode: GameMode.halveIt),
  _Mode('27', 'Bob’s 27', 'Doubles, pour souffrir.', mode: GameMode.bobs27),
  _Mode('T20', 'Entraînements', 'Solo, séries et routines.', training: true),
];

/// Règle en une phrase, à la place des options du X01.
const _rules = {
  GameMode.cricket: 'Ferme 20 à 15 et le bull en 3 marques. Ce que tu fermes avant les autres te rapporte des points.',
  GameMode.clock: 'Touche 1, 2, 3, jusqu’à 20, dans l’ordre. Simple, double ou triple, tout compte.',
  GameMode.shanghai: '7 manches. Manche 1 on vise le 1, puis le 2... Simple, double et triple au même tour : gagné.',
  GameMode.killer:
      'Chacun reçoit un numéro et 3 vies. Ton double te rend killer, puis tu chasses les doubles des autres.',
  GameMode.halveIt: '9 cibles imposées, départ à 40. Rien touché au tour : ton score est divisé par deux.',
  GameMode.bobs27: 'Départ à 27, de D1 à D20 puis bull. Un double rapporte sa valeur, un tour à vide la coûte.',
};

class _NewGameScreenState extends State<NewGameScreen> {
  _Mode _mode = _modes[1];
  late final List<String> _order = [AppState.owner];
  final List<String> _guests = [];
  String _out = 'Double';
  int _legs = 2;
  TrainingTarget _target = TrainingTarget.presets.first;
  int _series = 15;

  void _toggle(String name) => setState(() {
    if (_mode.training) {
      // Entraînement en solo : un seul joueur à la fois.
      _order
        ..clear()
        ..add(name);
    } else {
      _order.contains(name) ? _order.remove(name) : _order.add(name);
    }
  });

  void _addGuest() {
    if (_order.length >= 8) return;
    final name = 'Invité ${_guests.length + 1}';
    setState(() {
      _guests.add(name);
      _order.add(name);
    });
  }

  void _pickMode(_Mode m) {
    if (!m.playable) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            backgroundColor: Td.asphalteHaut,
            duration: const Duration(seconds: 2),
            content: Text('${m.title} arrive bientôt.', style: TdText.inter(15, 20, 400, Td.ink)),
          ),
        );
      return;
    }
    setState(() {
      _mode = m;
      if (m.training && _order.length > 1) _order.removeRange(1, _order.length);
    });
  }

  void _launch() {
    if (_mode.training) {
      // Pas de salon : on tire tout de suite.
      final cfg = GameConfig(
        players: [_order.isEmpty ? AppState.owner : _order.first],
        training: _target,
        trainingDarts: _series,
      );
      Navigator.of(
        context,
      ).pushAndRemoveUntil(MaterialPageRoute<void>(builder: (_) => gameScreenFor(cfg)), (r) => r.isFirst);
      return;
    }
    // Le salon s'ouvre : les potes rejoignent avec leur iPhone, puis "Lancer".
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SalonScreen(
          config: GameConfig(
            players: List.of(_order),
            startScore: _mode.start ?? 501,
            mode: _mode.mode,
            doubleOut: _out == 'Double',
            legsToWin: _legs,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Le propriétaire, puis les profils de la cible, puis les invités de cette partie.
    final everyone = [
      AppState.owner,
      for (final p in PlayerStore.instance.all)
        if (!p.owner) p.nickname,
      ..._guests,
    ];
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
                          Text(
                            'Choisis ton jeu',
                            style: TdText.inter(28, 34, 700, Td.ink).copyWith(letterSpacing: -0.3),
                          ),
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
                    Text(_mode.training ? 'Joueur' : "Joueurs, dans l'ordre", style: TdText.inter(13, 18, 600, Td.ink2)),
                    const SizedBox(height: Td.s3),
                    Wrap(
                      spacing: Td.s2,
                      runSpacing: Td.s2,
                      children: [
                        for (final n in everyone)
                          TdChip(
                            label: _order.contains(n) && !_mode.training ? '${_order.indexOf(n) + 1}. $n' : n,
                            icon: LucideIcons.user,
                            selected: _order.contains(n),
                            onTap: () => _toggle(n),
                          ),
                        if (!_mode.training) TdChip(label: 'Invité', icon: LucideIcons.plus, onTap: _addGuest),
                      ],
                    ),
                    if (_mode.training) ...[
                      const SizedBox(height: Td.s5),
                      Text('Cible', style: TdText.inter(13, 18, 600, Td.ink2)),
                      const SizedBox(height: Td.s3),
                      Wrap(
                        spacing: Td.s2,
                        runSpacing: Td.s2,
                        children: [
                          for (final t in TrainingTarget.presets)
                            TdChip(label: t.label, selected: t == _target, onTap: () => setState(() => _target = t)),
                        ],
                      ),
                      const SizedBox(height: Td.s5),
                      Text('Fléchettes par série', style: TdText.inter(13, 18, 600, Td.ink2)),
                      const SizedBox(height: Td.s3),
                      TdSegmented(
                        options: const ['9', '15', '30'],
                        value: '$_series',
                        touch: true,
                        onChanged: (v) => setState(() => _series = int.parse(v)),
                      ),
                    ] else if (_mode.start != null) ...[
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
                    ] else ...[
                      const SizedBox(height: Td.s5),
                      Text(_rules[_mode.mode]!, style: TdText.inter(15, 20, 400, Td.ink2)),
                    ],
                    const Spacer(),
                    Text(
                      _mode.training ? 'Toi, la cible, et rien d’autre.' : 'Les potes rejoignent depuis leur iPhone.',
                      style: TdText.inter(13, 18, 400, Td.ink3),
                    ),
                    const SizedBox(height: Td.s3),
                    TdButton(label: 'Lancer', icon: LucideIcons.play, onPressed: _launch),
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
