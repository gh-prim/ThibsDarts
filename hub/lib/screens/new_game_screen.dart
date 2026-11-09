import 'package:darts_engine/darts_engine.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../game_config.dart';
import '../players/player_store.dart';
import '../theme/tokens.dart';
import '../widgets/avatar.dart';
import '../widgets/controls.dart';
import '../widgets/dartboard.dart';
import '../widgets/game_widgets.dart';
import '../widgets/logo.dart';
import '../widgets/stage.dart';
import '../widgets/td_button.dart';
import 'mode_game_screen.dart';
import 'salon_screen.dart';
import 'training_screen.dart';

// Planche "Nouvelle partie Pi", version A des trois écrans.

Widget _label(String text) => Text(text, style: TdText.inter(13, 18, 600, Td.ink2));

/// Panneau en verre, comme sur les planches (bord, liseré clair, ombre portée).
BoxDecoration _glass({bool selected = false, double radius = Td.rXl, bool strong = false}) => BoxDecoration(
  color: selected ? Td.sunsetFond : (strong ? Td.verreMoyen : Td.verreLeger),
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: selected ? Td.sunset : Td.verreBord),
  boxShadow: selected
      ? const [BoxShadow(color: Color(0x40FF7A2F), blurRadius: 32, blurStyle: BlurStyle.outer)]
      : const [BoxShadow(color: Color(0x73000000), blurRadius: 24, offset: Offset(0, 8), blurStyle: BlurStyle.outer)],
);

Widget _header(BuildContext context, String title, {double size = 28, Widget? trailing}) => SizedBox(
  height: 44,
  child: Row(
    children: [
      TdIconButton(icon: LucideIcons.chevronLeft, label: 'Retour', onPressed: () => Navigator.of(context).pop()),
      const SizedBox(width: Td.s3),
      Expanded(
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TdText.inter(size, size + 6, 700, Td.ink).copyWith(letterSpacing: -0.3),
        ),
      ),
      if (trailing != null) trailing,
    ],
  ),
);

// MARK: Écran 1, Partie ou Entraînement (version A, deux affiches)

class PlayKindScreen extends StatelessWidget {
  const PlayKindScreen({super.key});

  @override
  Widget build(BuildContext context) {
    void open(bool practice) =>
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => NewGameScreen(practice: practice)));
    final faces = [
      AppState.owner,
      for (final p in PlayerStore.instance.all)
        if (!p.owner) p.nickname,
    ].take(3).toList();
    return Scaffold(
      backgroundColor: Td.beton,
      body: Stage(
        child: Padding(
          padding: const EdgeInsets.all(Td.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(
                context,
                'On joue comment ?',
                trailing: const Logo(variant: LogoVariant.icon, height: 40),
              ),
              const SizedBox(height: Td.s4),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: Td.s4,
                  children: [
                    Expanded(
                      child: _Poster(
                        onTap: () => open(false),
                        eyebrow: 'À plusieurs',
                        title: 'Partie',
                        color: Td.sunset,
                        middle: Row(
                          children: [
                            for (var i = 0; i < faces.length; i++)
                              Transform.translate(
                                offset: Offset(-14.0 * i, 0),
                                child: Container(
                                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Td.beton),
                                  padding: const EdgeInsets.all(3),
                                  child: Avatar(name: faces[i], size: 64),
                                ),
                              ),
                            Transform.translate(
                              offset: Offset(-14.0 * faces.length, 0),
                              child: Container(
                                width: 70,
                                height: 70,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Td.sunsetFond,
                                  border: Border.all(color: Td.sunset, width: 2),
                                ),
                                child: const Icon(LucideIcons.plus, size: 24, color: Td.sunset),
                              ),
                            ),
                          ],
                        ),
                        line: 'Les potes rejoignent avec leur iPhone.',
                        icon: LucideIcons.qrCode,
                        foot: 'Salon avec QR code, 8 joueurs max.',
                      ),
                    ),
                    Expanded(
                      child: _Poster(
                        onTap: () => open(true),
                        eyebrow: 'En solo',
                        title: 'Entraînement',
                        color: Td.ciel,
                        backdrop: const Positioned(
                          right: -150,
                          top: 50,
                          width: 380,
                          height: 380,
                          child: IgnorePointer(
                            child: Opacity(
                              opacity: 0.9,
                              child: Dartboard(aimed: DartThrow.triple(20), dim: true),
                            ),
                          ),
                        ),
                        line: 'Pas de salon. Tu tires tout de suite.',
                        icon: LucideIcons.target,
                        foot: 'Volées libres, séries, tous les jeux.',
                        maxTextWidth: 300,
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

class _Poster extends StatelessWidget {
  const _Poster({
    required this.onTap,
    required this.eyebrow,
    required this.title,
    required this.color,
    required this.line,
    required this.icon,
    required this.foot,
    this.middle,
    this.backdrop,
    this.maxTextWidth,
  });

  final VoidCallback onTap;
  final String eyebrow, title, line, foot;
  final Color color;
  final IconData icon;
  final Widget? middle;
  final Widget? backdrop;
  final double? maxTextWidth;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: _glass(strong: true),
        child: Stack(
          children: [
            if (backdrop != null) backdrop!,
            Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: Td.s1,
                    children: [
                      _label(eyebrow),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          title,
                          style: TdText.rounded(64, 900, color, height: 64).copyWith(letterSpacing: -1.5),
                        ),
                      ),
                    ],
                  ),
                  middle ?? const SizedBox.shrink(),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxTextWidth ?? double.infinity),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: Td.s3,
                      children: [
                        Text(line, style: TdText.inter(22, 28, 700, Td.ink)),
                        Row(
                          spacing: Td.s2,
                          children: [
                            Icon(icon, size: 20, color: Td.ink2),
                            Expanded(child: Text(foot, style: TdText.inter(15, 20, 400, Td.ink2))),
                          ],
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
    );
  }
}

// MARK: Jeux

enum _Drill { volleys, target }

class _Mode {
  const _Mode(
    this.glyph,
    this.title,
    this.short,
    this.rule, {
    this.start,
    this.mode,
    this.drill,
    this.aimed,
    this.aimSector,
    this.heat = const {},
  });

  final String glyph;

  /// "Le classique", "Cricket".
  final String title;

  /// Nom court pour les petites tuiles.
  final String short;

  /// La règle en une phrase.
  final String rule;
  final int? start;
  final GameMode? mode;
  final _Drill? drill;

  // Ce que montre le plateau pour ce jeu.
  final DartThrow? aimed;
  final int? aimSector;
  final Set<int> heat;
}

const _x01 = [
  _Mode(
    '301',
    'Le sprint',
    'Sprint',
    'Descends de 301 à zéro. Court, nerveux, sans temps mort.',
    start: 301,
    aimed: DartThrow.double(20),
  ),
  _Mode(
    '501',
    'Le classique',
    'Classique',
    'Descends de 501 à zéro. Le grand classique des bars.',
    start: 501,
    aimed: DartThrow.double(20),
  ),
];

const _cricket = _Mode(
  '15+',
  'Cricket',
  'Cricket',
  'Ferme 20 à 15 et le bull en 3 marques. Ce que tu fermes avant les autres te rapporte des points.',
  mode: GameMode.cricket,
  heat: {20, 19, 18, 17, 16, 15, 25},
);
const _clock = _Mode(
  '1>20',
  'Around the clock',
  'Clock',
  'Touche 1, 2, 3, jusqu’à 20, dans l’ordre. Simple, double ou triple, tout compte.',
  mode: GameMode.clock,
  aimSector: 1,
);
const _shanghai = _Mode(
  'S·D·T',
  'Shanghai',
  'Shanghai',
  '7 manches. Manche 1 on vise le 1, puis le 2... Simple, double et triple au même tour : gagné.',
  mode: GameMode.shanghai,
  aimSector: 1,
);
const _killer = _Mode(
  'K',
  'Killer',
  'Killer',
  'Chacun reçoit un numéro et 3 vies. Ton double te rend killer, puis tu chasses les doubles des autres.',
  mode: GameMode.killer,
);
const _halveIt = _Mode(
  '½',
  'Halve-it',
  'Halve-it',
  '9 cibles imposées, départ à 40. Rien touché au tour : ton score est divisé par deux.',
  mode: GameMode.halveIt,
  aimSector: 15,
);
const _bobs = _Mode(
  '27',
  'Bob’s 27',
  'Bob’s 27',
  'Départ à 27, de D1 à D20 puis bull. Un double rapporte sa valeur, un tour à vide la coûte.',
  mode: GameMode.bobs27,
  aimed: DartThrow.double(1),
);

const _partyModes = [..._x01, _cricket, _clock, _shanghai, _killer, _halveIt, _bobs];

const _volleys = _Mode('3×', 'Volées libres', 'Volées', 'Trois fléchettes, on compte.', drill: _Drill.volleys);
const _series = _Mode('T20', 'Série sur cible', 'Série', 'Une cible, et on enchaîne.', drill: _Drill.target);
const _soloGames = [..._x01, _cricket, _clock, _shanghai, _halveIt, _bobs];

/// "Choisis ton jeu" (Partie) ou "Entraînement" (solo), planche Nouvelle partie Pi, version A.
class NewGameScreen extends StatefulWidget {
  const NewGameScreen({super.key, this.practice = false});

  /// Entraînement en solo : sans salon, un seul joueur.
  final bool practice;

  @override
  State<NewGameScreen> createState() => _NewGameScreenState();
}

class _NewGameScreenState extends State<NewGameScreen> {
  bool get _practice => widget.practice;

  late _Mode _mode = _practice ? _series : _partyModes[1];
  late final List<String> _order = [AppState.owner];
  final List<String> _guests = [];
  String _out = 'Double';
  int _legs = 2;
  TrainingTarget _target = TrainingTarget.presets.first;
  int _darts = 15;
  String _volleyCount = '10';

  String get _shooter => _order.isEmpty ? AppState.owner : _order.first;

  void _toggle(String name) => setState(() {
    if (_practice) {
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
        players: [_shooter],
        practice: true,
        startScore: _mode.start ?? 501,
        doubleOut: _out == 'Double',
        mode: _mode.mode,
        training: _mode.drill == _Drill.target ? _target : null,
        trainingDarts: _darts,
        freeVolleys: _mode.drill == _Drill.volleys ? (int.tryParse(_volleyCount) ?? 0) : null,
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

  List<String> get _everyone => [
    AppState.owner,
    for (final p in PlayerStore.instance.all)
      if (!p.owner) p.nickname,
    ..._guests,
  ];

  /// Règle du jeu choisi ; pour un X01, elle suit la sortie choisie.
  String get _rule {
    final start = _mode.start;
    if (start == null) return _mode.rule;
    return _out == 'Double'
        ? 'Descends de $start à zéro. La dernière fléchette tombe dans un double.'
        : 'Descends de $start à zéro. N’importe quelle fléchette peut finir.';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Td.beton,
    body: Stage(child: _practice ? _practiceLayout() : _partyLayout()),
  );

  // MARK: Écran 2a, Choisis ton jeu (version A, jeu en vedette)

  Widget _partyLayout() => Padding(
    padding: const EdgeInsets.all(Td.s4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Td.s4,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Td.s3,
            children: [
              _header(context, 'Choisis ton jeu'),
              Expanded(child: _hero()),
              Column(
                spacing: Td.s2,
                children: [
                  for (var r = 0; r < 2; r++)
                    Row(
                      spacing: Td.s2,
                      children: [
                        for (final m in _partyModes.sublist(r * 4, r * 4 + 4)) Expanded(child: _pill(m)),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
        Container(
          width: 336,
          padding: const EdgeInsets.all(Td.s4),
          decoration: _glass(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _label("Joueurs, dans l'ordre"),
              const SizedBox(height: Td.s3),
              Wrap(
                spacing: Td.s2,
                runSpacing: Td.s2,
                children: [
                  for (final n in _everyone)
                    TdChip(
                      label: _order.contains(n) ? '${_order.indexOf(n) + 1}. $n' : n,
                      icon: LucideIcons.user,
                      selected: _order.contains(n),
                      onTap: () => _toggle(n),
                    ),
                  TdChip(label: 'Invité', icon: LucideIcons.plus, onTap: _addGuest),
                ],
              ),
              if (_mode.start != null) ...[
                const SizedBox(height: Td.s5),
                _label('Sortie'),
                const SizedBox(height: Td.s3),
                TdSegmented(
                  options: const ['Double', 'Simple'],
                  value: _out,
                  touch: true,
                  onChanged: (v) => setState(() => _out = v),
                ),
                const SizedBox(height: Td.s5),
                _label('Manches gagnantes'),
                const SizedBox(height: Td.s3),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TdStepper(value: _legs, min: 1, max: 5, onChanged: (v) => setState(() => _legs = v)),
                ),
              ],
              const Spacer(),
              Text("Le salon s'ouvre, les potes rejoignent avec leur iPhone.", style: TdText.inter(13, 18, 400, Td.ink3)),
              const SizedBox(height: Td.s3),
              TdButton(label: 'Ouvrir le salon', icon: LucideIcons.play, onPressed: _launch),
            ],
          ),
        ),
      ],
    ),
  );

  /// Le jeu choisi en grand, plateau en fond.
  Widget _hero() => Container(
    clipBehavior: Clip.antiAlias,
    decoration: _glass(selected: true),
    child: Stack(
      children: [
        Positioned(
          right: -90,
          top: -40,
          width: 340,
          height: 340,
          child: IgnorePointer(child: _board(_mode)),
        ),
        Padding(
          padding: const EdgeInsets.all(Td.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _label(_mode.title),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Td.s2,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _mode.glyph,
                        style: TdText.rounded(140, 900, Td.sunset, height: 132).copyWith(letterSpacing: -4),
                      ),
                    ),
                    Text(_rule, style: TdText.inter(17, 22, 400, Td.ink2)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _board(_Mode m, {DartThrow? aimed}) => Dartboard(
    aimed: aimed ?? m.aimed,
    aimSector: m.aimSector,
    heat: m.heat,
    dim: m.heat.isEmpty,
  );

  /// Petite tuile de jeu (72 px de haut) : glyphe et nom court.
  Widget _pill(_Mode m) {
    final on = m == _mode;
    return Pressable(
      onTap: () => setState(() => _mode = m),
      child: AnimatedContainer(
        duration: Td.rapide,
        height: Td.ciblePi,
        padding: const EdgeInsets.symmetric(horizontal: Td.s3),
        decoration: BoxDecoration(
          color: on ? Td.sunsetFond : Td.verreLeger,
          borderRadius: BorderRadius.circular(Td.rMd),
          border: Border.all(color: on ? Td.sunset : Td.verreBord),
        ),
        child: Row(
          spacing: 10,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 44),
              child: Text(m.glyph, style: TdText.rounded(22, 900, on ? Td.sunset : Td.ink)),
            ),
            Expanded(
              child: Text(
                m.short,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TdText.inter(15, 20, 600, Td.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // MARK: Écran 2b, Entraînement (version A, série sur cible)

  Widget _practiceLayout() {
    final record = switch (_mode.drill) {
      _Drill.target => practiceRecord(_shooter, target: _target, darts: _darts),
      _Drill.volleys => practiceRecord(_shooter),
      null => null,
    };
    return Padding(
      padding: const EdgeInsets.all(Td.s3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Td.s3,
        children: [
          SizedBox(
            width: 300,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context, 'Entraînement', size: 22),
                const SizedBox(height: 14),
                _label('Routines'),
                const SizedBox(height: 10),
                _routine(_volleys),
                const SizedBox(height: 10),
                _routine(_series),
                const SizedBox(height: 16),
                _label('Jeux en solo'),
                const SizedBox(height: 10),
                Expanded(
                  child: Column(
                    spacing: Td.s2,
                    children: [
                      for (var r = 0; r < 3; r++)
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            spacing: Td.s2,
                            children: [
                              for (var c = 0; c < 3; c++)
                                Expanded(
                                  child: r * 3 + c < _soloGames.length
                                      ? _soloTile(_soloGames[r * 3 + c])
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
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: Td.s2,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380, maxHeight: 380),
                  child: _board(
                    _mode,
                    aimed: _mode.drill == _Drill.target
                        ? (_target.sector == 25 ? null : DartThrow(_target.sector, _target.multiplier))
                        : null,
                  ),
                ),
                _caption(),
              ],
            ),
          ),
          Container(
            width: 300,
            padding: const EdgeInsets.all(Td.s4),
            decoration: _glass(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _label('Qui tire'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: Td.s2,
                  runSpacing: Td.s2,
                  children: [
                    for (final n in _everyone)
                      TdChip(label: n, icon: LucideIcons.user, selected: n == _shooter, onTap: () => _toggle(n)),
                  ],
                ),
                ..._practiceOptions(),
                if (record != null || _mode.drill != null) ...[
                  const SizedBox(height: Td.s4),
                  _mode.drill == _Drill.target
                      ? KpiTile(
                          label: 'Ton record sur ${_target.label}',
                          value: record == null ? '-' : '$record',
                          unit: 'sur $_darts',
                        )
                      : KpiTile(label: 'Ta meilleure volée', value: record == null ? '-' : '$record', unit: 'points'),
                ],
                const Spacer(),
                TdButton(label: 'Lancer', icon: LucideIcons.play, onPressed: _launch),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _caption() {
    final text = switch (_mode.drill) {
      _Drill.target => null,
      _Drill.volleys =>
        _volleyCount == 'Sans fin' ? 'Des volées de 3, tant que tu veux.' : '$_volleyCount volées de 3. On compte tout.',
      null => _rule,
    };
    if (text != null) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Text(text, textAlign: TextAlign.center, style: TdText.inter(15, 20, 400, Td.ink2)),
      );
    }
    return Text.rich(
      TextSpan(
        style: TdText.inter(15, 20, 400, Td.ink2),
        children: [
          TextSpan(text: '$_darts fléchettes, toutes au '),
          TextSpan(text: _target.label, style: TdText.inter(15, 20, 700, Td.ciel)),
          const TextSpan(text: '.'),
        ],
      ),
    );
  }

  List<Widget> _practiceOptions() {
    switch (_mode.drill) {
      case _Drill.volleys:
        return [
          const SizedBox(height: 14),
          _label('Volées'),
          const SizedBox(height: 10),
          TdSegmented(
            options: const ['10', '20', 'Sans fin'],
            value: _volleyCount,
            touch: true,
            onChanged: (v) => setState(() => _volleyCount = v),
          ),
        ];
      case _Drill.target:
        return [
          const SizedBox(height: 14),
          _label('Cible'),
          const SizedBox(height: 10),
          Wrap(
            spacing: Td.s2,
            runSpacing: Td.s2,
            children: [
              for (final t in TrainingTarget.presets)
                TdChip(label: t.label, selected: t == _target, onTap: () => setState(() => _target = t)),
            ],
          ),
          const SizedBox(height: 14),
          _label('Fléchettes'),
          const SizedBox(height: 10),
          TdSegmented(
            options: const ['9', '15', '30'],
            value: '$_darts',
            touch: true,
            onChanged: (v) => setState(() => _darts = int.parse(v)),
          ),
        ];
      case null:
        if (_mode.start == null) return const [];
        return [
          const SizedBox(height: 14),
          _label('Sortie'),
          const SizedBox(height: 10),
          TdSegmented(
            options: const ['Double', 'Simple'],
            value: _out,
            touch: true,
            onChanged: (v) => setState(() => _out = v),
          ),
        ];
    }
  }

  /// Routine (72 px) : glyphe, nom et une ligne.
  Widget _routine(_Mode m) {
    final on = m == _mode;
    return Pressable(
      onTap: () => setState(() => _mode = m),
      child: AnimatedContainer(
        duration: Td.rapide,
        height: Td.ciblePi,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: on ? Td.sunsetFond : Td.verreLeger,
          borderRadius: BorderRadius.circular(Td.rLg),
          border: Border.all(color: on ? Td.sunset : Td.verreBord),
        ),
        child: Row(
          spacing: Td.s3,
          children: [
            SizedBox(
              width: 52,
              child: Text(m.glyph, style: TdText.rounded(26, 900, on ? Td.sunset : Td.ink2)),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.title, style: TdText.inter(17, 22, 600, Td.ink)),
                  Text(
                    m.rule,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TdText.inter(13, 18, 400, Td.ink2),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Jeu en solo : petite tuile, glyphe et nom court.
  Widget _soloTile(_Mode m) {
    final on = m == _mode;
    return Pressable(
      onTap: () => setState(() => _mode = m),
      child: AnimatedContainer(
        duration: Td.rapide,
        constraints: const BoxConstraints(minHeight: Td.ciblePi),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: Td.s2),
        decoration: BoxDecoration(
          color: on ? Td.sunsetFond : Td.verreLeger,
          borderRadius: BorderRadius.circular(Td.rMd),
          border: Border.all(color: on ? Td.sunset : Td.verreBord),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 2,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(m.glyph, style: TdText.rounded(20, 900, on ? Td.sunset : Td.ink2, height: 22)),
            ),
            Text(
              m.short,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TdText.inter(12, 16, 600, Td.ink),
            ),
          ],
        ),
      ),
    );
  }
}
