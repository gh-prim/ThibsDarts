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

/// Premier écran de "Nouvelle partie" : une vraie partie, ou un entraînement en solo.
class PlayKindScreen extends StatelessWidget {
  const PlayKindScreen({super.key});

  @override
  Widget build(BuildContext context) {
    void open(bool practice) =>
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => NewGameScreen(practice: practice)));
    return Scaffold(
      backgroundColor: Td.beton,
      body: Stage(
        child: Padding(
          padding: const EdgeInsets.all(Td.s4),
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
                      'Nouvelle partie',
                      style: TdText.inter(28, 34, 700, Td.ink).copyWith(letterSpacing: -0.3),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Td.s4),
              Expanded(
                child: Row(
                  spacing: Td.s4,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ModeTile(
                        glyph: 'VS',
                        title: 'Partie',
                        desc: 'À plusieurs. Les potes rejoignent depuis leur iPhone.',
                        onTap: () => open(false),
                      ),
                    ),
                    Expanded(
                      child: ModeTile(
                        glyph: 'T20',
                        title: 'Entraînement',
                        desc: 'En solo. Tous les jeux, plus les volées libres.',
                        onTap: () => open(true),
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

enum _Drill { volleys, target }

class _Mode {
  const _Mode(this.glyph, this.title, this.desc, {this.start, this.mode, this.drill});
  final String glyph, title, desc;
  final int? start;
  final GameMode? mode;

  /// Entraînement dédié (volées libres, série sur cible).
  final _Drill? drill;
}

const _x01 = [
  _Mode('301', 'Le sprint', 'Double à la sortie.', start: 301),
  _Mode('501', 'Le classique', 'Double à la sortie.', start: 501),
];

const _games = [
  _Mode('15+', 'Cricket', 'Ferme, marque, chambre.', mode: GameMode.cricket),
  _Mode('1>20', 'Around the clock', 'De 1 à 20, dans l’ordre.', mode: GameMode.clock),
  _Mode('S·D·T', 'Shanghai', 'S, D, T au même tour.', mode: GameMode.shanghai),
];

const _killer = _Mode('K', 'Killer', 'Trois vies. Pas d’amis.', mode: GameMode.killer);

const _late = [
  _Mode('½', 'Halve-it', 'Rate, ton score fond.', mode: GameMode.halveIt),
  _Mode('27', 'Bob’s 27', 'Doubles, pour souffrir.', mode: GameMode.bobs27),
];

/// Partie : 8 jeux. Entraînement : volées libres, série sur cible, et les jeux qui se jouent seul.
const _partyModes = [..._x01, ..._games, _killer, ..._late];
const _practiceModes = [
  _Mode('3×', 'Volées libres', 'Trois fléchettes, on compte.', drill: _Drill.volleys),
  _Mode('T20', 'Série sur cible', 'Une cible, et on enchaîne.', drill: _Drill.target),
  ..._x01,
  ..._games,
  ..._late,
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

/// "Choisis ton jeu" (planche NouvellePartie), pour une partie ou un entraînement.
class NewGameScreen extends StatefulWidget {
  const NewGameScreen({super.key, this.practice = false});

  /// Entraînement en solo : sans salon, un seul joueur.
  final bool practice;

  @override
  State<NewGameScreen> createState() => _NewGameScreenState();
}

class _NewGameScreenState extends State<NewGameScreen> {
  bool get _practice => widget.practice;
  List<_Mode> get _modes => _practice ? _practiceModes : _partyModes;

  late _Mode _mode = _practice ? _practiceModes.first : _partyModes[1];
  late final List<String> _order = [AppState.owner];
  final List<String> _guests = [];
  String _out = 'Double';
  int _legs = 2;
  TrainingTarget _target = TrainingTarget.presets.first;
  int _series = 15;
  String _volleys = '10';

  void _toggle(String name) => setState(() {
    if (_practice) {
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

  void _launch() {
    if (_practice) {
      // Pas de salon : on tire tout de suite.
      final cfg = GameConfig(
        players: [_order.isEmpty ? AppState.owner : _order.first],
        practice: true,
        startScore: _mode.start ?? 501,
        doubleOut: _out == 'Double',
        mode: _mode.mode,
        training: _mode.drill == _Drill.target ? _target : null,
        trainingDarts: _series,
        freeVolleys: _mode.drill == _Drill.volleys ? (int.tryParse(_volleys) ?? 0) : null,
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

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(top: Td.s5, bottom: Td.s3),
    child: Text(text, style: TdText.inter(13, 18, 600, Td.ink2)),
  );

  /// Réglages propres au jeu choisi, sous les joueurs.
  List<Widget> _options() {
    switch (_mode.drill) {
      case _Drill.volleys:
        return [
          _label('Volées'),
          TdSegmented(
            options: const ['10', '20', 'Sans fin'],
            value: _volleys,
            touch: true,
            onChanged: (v) => setState(() => _volleys = v),
          ),
        ];
      case _Drill.target:
        return [
          _label('Cible'),
          Wrap(
            spacing: Td.s2,
            runSpacing: Td.s2,
            children: [
              for (final t in TrainingTarget.presets)
                TdChip(label: t.label, selected: t == _target, onTap: () => setState(() => _target = t)),
            ],
          ),
          _label('Fléchettes par série'),
          TdSegmented(
            options: const ['9', '15', '30'],
            value: '$_series',
            touch: true,
            onChanged: (v) => setState(() => _series = int.parse(v)),
          ),
        ];
      case null:
        if (_mode.start == null) {
          return [
            const SizedBox(height: Td.s5),
            Text(_rules[_mode.mode]!, style: TdText.inter(15, 20, 400, Td.ink2)),
          ];
        }
        return [
          _label('Sortie'),
          TdSegmented(
            options: const ['Double', 'Simple'],
            value: _out,
            touch: true,
            onChanged: (v) => setState(() => _out = v),
          ),
          if (!_practice) ...[
            _label('Manches gagnantes'),
            Align(
              alignment: Alignment.centerLeft,
              child: TdStepper(value: _legs, min: 1, max: 5, onChanged: (v) => setState(() => _legs = v)),
            ),
          ],
        ];
    }
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
    final modes = _modes;
    final cols = modes.length > 8 ? 3 : 4;
    final rows = (modes.length / cols).ceil();
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
                            _practice ? 'Choisis ton entraînement' : 'Choisis ton jeu',
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
                          for (var r = 0; r < rows; r++)
                            Expanded(
                              child: Row(
                                spacing: Td.s2,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (var c = 0; c < cols; c++)
                                    Expanded(
                                      child: r * cols + c < modes.length
                                          ? ModeTile(
                                              glyph: modes[r * cols + c].glyph,
                                              title: modes[r * cols + c].title,
                                              desc: modes[r * cols + c].desc,
                                              selected: modes[r * cols + c] == _mode,
                                              onTap: () => setState(() => _mode = modes[r * cols + c]),
                                            )
                                          : const SizedBox.shrink(),
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
                    Text(_practice ? 'Joueur' : "Joueurs, dans l'ordre", style: TdText.inter(13, 18, 600, Td.ink2)),
                    const SizedBox(height: Td.s3),
                    Wrap(
                      spacing: Td.s2,
                      runSpacing: Td.s2,
                      children: [
                        for (final n in everyone)
                          TdChip(
                            label: _order.contains(n) && !_practice ? '${_order.indexOf(n) + 1}. $n' : n,
                            icon: LucideIcons.user,
                            selected: _order.contains(n),
                            onTap: () => _toggle(n),
                          ),
                        if (!_practice) TdChip(label: 'Invité', icon: LucideIcons.plus, onTap: _addGuest),
                      ],
                    ),
                    ..._options(),
                    const Spacer(),
                    Text(
                      _practice ? 'Toi, la cible, et rien d’autre.' : 'Les potes rejoignent depuis leur iPhone.',
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
