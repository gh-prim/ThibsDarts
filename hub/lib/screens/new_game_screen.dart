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
import '../history/history_store.dart';
import 'mode_game_screen.dart';
import 'salon_screen.dart';
import 'trainer_screen.dart';
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
      ?trailing,
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
            ?backdrop,
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

const _bermuda = _Mode(
  '12>B',
  'Bermuda',
  'Bermuda',
  '12 cibles : 12, 13, 14, un double, 15, 16, 17, un triple, 18, 19, 20 et le bull. Rate tout : ton score est divisé par deux.',
  mode: GameMode.bermuda,
  aimSector: 12,
);
const _gotcha = _Mode(
  '=0',
  'Gotcha',
  'Gotcha',
  'Premier à 301 pile. Si tu tombes sur le score d’un pote, il repart à 0.',
  mode: GameMode.gotcha,
  aimed: DartThrow.triple(20),
);

const _partyModes = [..._x01, _cricket, _clock, _shanghai, _killer, _halveIt, _bobs, _bermuda, _gotcha];

/// Variantes du Cricket : nom et règle.
const _cricketVariants = {
  CricketVariant.classic: ('Classique', 'Ferme 20 à 15 et le bull. Marque sur ce qui est encore ouvert chez les autres.'),
  CricketVariant.noScore: ('No Score', 'Fermer, c’est tout. Le premier qui a tout fermé gagne.'),
  CricketVariant.cutThroat: ('Cut-Throat', 'Tes points vont chez les autres. Le plus petit score gagne.'),
  CricketVariant.random: ('Random', '6 numéros tirés au hasard, plus le bull. Nouvelle cible à chaque partie.'),
  CricketVariant.tactic: ('Tactic', 'De 20 à 10, plus le bull. Plus long, plus vicieux.'),
};

// MARK: Entraînements (planche Choisis ton entraînement)

enum _Kind { trainer, drill, mode, bot }

/// Un entraînement de la planche : tuile, règle, réglage.
class _Pick {
  const _Pick(
    this.glyph,
    this.title,
    this.desc,
    this.rule, {
    required this.kind,
    this.mode,
    this.drill,
    this.optLabel,
    this.opts = const [],
    this.opt,
    this.recUnit = 'pts',
  });

  final String glyph;
  final String title;
  final String desc;
  final String rule;
  final _Kind kind;
  final GameMode? mode;
  final _Drill? drill;
  final String? optLabel;
  final List<String> opts;
  final String? opt;
  final String recUnit;
}

const _botLevels = ['30', '45', '60', '75', '90', '105'];

const _families = <String, (String, String, List<_Pick>)>{
  'Finir': (
    'Finir',
    'Les sorties. Là où les manches se gagnent.',
    [
      _Pick('61+', 'Catch 40', 'Finis 61 à 100, 6 fléchettes max.', 'Chaque score de 61 à 100 à finir sur un double. 3 points si tu sors en 3 fléchettes, 2 en 4 à 6, 0 sinon.', kind: _Kind.trainer, mode: GameMode.catch40, recUnit: 'pts sur 120'),
      _Pick('121', '9 Darts Double Out', 'Finis 121 en 9 fléchettes.', 'Trois volées pour finir 121, ou 81 si tu veux souffler. Double obligatoire à la fin. 10 tentatives.', kind: _Kind.trainer, mode: GameMode.nineDarts, optLabel: 'Score de départ', opts: ['121', '81'], opt: '121', recUnit: 'réussis sur 10'),
      _Pick('?', 'Checkout au hasard', 'Un score tiré, 3 volées.', 'Le Pi tire un score, tu as 3 volées pour le finir. 10 scores, on compte les réussites.', kind: _Kind.trainer, mode: GameMode.randomCheckout, optLabel: 'Plage de scores', opts: ['2-60', '61-110', '111-170'], opt: '61-110', recUnit: 'réussis sur 10'),
      _Pick('170', '170', 'La sortie max, en 9 fléchettes.', 'Pars de 170 et finis en 9 fléchettes max. 10 tentatives à la suite.', kind: _Kind.trainer, mode: GameMode.ton70, recUnit: 'réussis sur 10'),
      _Pick('41+', '41-60', 'Simple puis double, 3 fléchettes.', 'Chaque score de 41 à 60, 3 fléchettes pour le finir. Le geste de base : simple, puis double.', kind: _Kind.trainer, mode: GameMode.fortyOne, recUnit: 'réussis sur 20'),
      _Pick('27', 'Bob’s 27', 'D1 à D20 puis bull.', 'Départ à 27, de D1 à D20 puis bull. Un double rapporte sa valeur, un tour à vide la coûte.', kind: _Kind.mode, mode: GameMode.bobs27),
    ],
  ),
  'Viser': (
    'Viser',
    'La précision. Un numéro, un geste.',
    [
      _Pick('T20', 'Série sur cible', 'X fléchettes sur une cible.', 'Tu choisis la cible et le nombre de fléchettes. On compte ce qui rentre.', kind: _Kind.drill, drill: _Drill.target),
      _Pick('1>B', 'Tour du monde', 'Une volée par numéro, on compte.', 'Une volée sur le 1, puis le 2, jusqu’au bull. Touché ou pas, on avance. Chaque touche rapporte.', kind: _Kind.trainer, mode: GameMode.roundTheWorld, optLabel: 'Ce qui compte', opts: ['Simple', 'Double', 'Triple'], opt: 'Simple'),
      _Pick('JDC', 'JDC Challenge', 'Shanghai, doubles, Shanghai.', 'Shanghai du 10 au 15, un double par numéro de 1 au bull, puis Shanghai du 15 au 20. Simple, double, triple en une volée : bonus.', kind: _Kind.trainer, mode: GameMode.jdc),
      _Pick('99', '99 fléchettes', '33 volées sur une cible.', '33 volées sur la même cible. Total des points, moyenne par volée.', kind: _Kind.trainer, mode: GameMode.darts99, optLabel: 'Cible', opts: ['20', '19', 'Bull'], opt: '20'),
      _Pick('1>20', 'Around the clock', 'De 1 à 20, dans l’ordre.', 'Touche 1, 2, 3, jusqu’à 20, dans l’ordre. Tant que tu ne touches pas, tu restes dessus.', kind: _Kind.mode, mode: GameMode.clock),
      _Pick('S·D·T', 'Shanghai', '7 manches, S, D, T.', '7 manches. Manche 1 on vise le 1, puis le 2. Simple, double et triple au même tour : gagné.', kind: _Kind.mode, mode: GameMode.shanghai),
    ],
  ),
  'Scorer': (
    'Scorer',
    'Le scoring. Remplir le tableau, sans réfléchir.',
    [
      _Pick('3×', 'Volées libres', 'Tire, on compte.', 'Des volées de 3, sans cible imposée. Tu choisis combien.', kind: _Kind.drill, drill: _Drill.volleys, optLabel: 'Volées', opts: ['10', '20', 'Sans fin'], opt: '10', recUnit: 'pts en une volée'),
      _Pick('+', 'Count Up', 'X volées, tout compte.', 'Tu additionnes tout pendant 8 volées. Simple comme un dimanche.', kind: _Kind.trainer, mode: GameMode.countUp, optLabel: 'Volées', opts: ['8', '10', '20'], opt: '8'),
      _Pick('15+', 'Cricket Count Up', 'Que des marques.', '15 à 20 et bull. Simple 1 marque, double 2, triple 3. 8 volées pour en faire le plus.', kind: _Kind.trainer, mode: GameMode.cricketCountUp, recUnit: 'marques'),
      _Pick('501', 'X01 en solo', 'Descends à zéro, seul.', 'Descends à zéro, la dernière fléchette dans un double. Pour bosser ton rythme.', kind: _Kind.mode, optLabel: 'Départ', opts: ['301', '501'], opt: '501'),
      _Pick('½', 'Halve-it', '9 cibles, départ à 40.', '9 cibles imposées, départ à 40. Rien touché au tour : ton score est divisé par deux.', kind: _Kind.mode, mode: GameMode.halveIt),
    ],
  ),
  'Robot': (
    'Contre le robot',
    'Un adversaire qui ne fatigue jamais.',
    [
      _Pick('501', '501 contre le robot', 'Choisis son niveau.', 'Un 501 double out contre le robot. Son niveau, c’est sa moyenne sur 3 fléchettes.', kind: _Kind.bot, optLabel: 'Niveau du robot', opts: _botLevels, opt: '60', recUnit: 'niveau battu'),
      _Pick('15+', 'Cricket contre le robot', 'Il ferme, tu chambres.', 'Un Cricket classique contre le robot. Plus il est fort, plus il ferme vite.', kind: _Kind.bot, mode: GameMode.cricket, optLabel: 'Niveau du robot', opts: _botLevels, opt: '45', recUnit: 'niveau battu'),
    ],
  ),
};

/// Plus haut niveau de robot battu par [name] à ce jeu, null si jamais.
int? _botBeaten(String name, GameMode? mode) {
  final id = HistoryStore.playerId(name);
  int? best;
  for (final m in HistoryStore.instance.all()) {
    final bot = (m['bot'] as num?)?.toInt();
    if (bot == null || m['kind'] != (mode?.name ?? 'x01')) continue;
    final won = (m['players'] as List).any((p) => (p as Map)['id'] == id && p['won'] == true);
    if (won && (best == null || bot > best)) best = bot;
  }
  return best;
}

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

  late _Mode _mode = _partyModes[1];
  String _fam = 'Finir';
  final Map<String, int> _sel = {'Finir': 0, 'Viser': 0, 'Scorer': 0, 'Robot': 0};
  final Map<String, String> _opts = {};
  String _botFirst = 'Toi';
  CricketVariant _variant = CricketVariant.classic;
  String _goal = '301';

  _Pick get _pick => _families[_fam]!.$3[_sel[_fam]!];
  String? get _opt => _opts[_pick.title] ?? _pick.opt;

  /// Réglage du jeu choisi, en valeur pour la config.
  int get _option {
    final o = _opt;
    return switch (_pick.mode) {
      GameMode.nineDarts => int.parse(o ?? '121'),
      GameMode.randomCheckout => _pick.opts.indexOf(o ?? '61-110').clamp(0, 2),
      GameMode.darts99 => o == 'Bull' ? 25 : int.parse(o ?? '20'),
      GameMode.roundTheWorld => _pick.opts.indexOf(o ?? 'Simple') + 1,
      GameMode.countUp => int.parse(o ?? '8'),
      _ => 0,
    };
  }
  late final List<String> _order = [AppState.owner];
  final List<String> _guests = [];
  String _out = 'Double';
  int _legs = 2;
  TrainingTarget _target = TrainingTarget.presets.first;
  int _darts = 15;

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
      final p = _pick;
      final bot = p.kind == _Kind.bot;
      final cfg = GameConfig(
        players: bot
            ? (_botFirst == 'Toi' ? [_shooter, GameConfig.botName] : [GameConfig.botName, _shooter])
            : [_shooter],
        practice: true,
        startScore: p.mode == null && p.kind == _Kind.mode ? int.parse(_opt ?? '501') : 501,
        doubleOut: true,
        mode: p.kind == _Kind.drill ? null : p.mode,
        training: p.drill == _Drill.target ? _target : null,
        trainingDarts: _darts,
        freeVolleys: p.drill == _Drill.volleys ? (int.tryParse(_opt ?? '10') ?? 0) : null,
        botLevel: bot ? int.parse(_opt ?? '60') : null,
        option: _option,
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
            startScore: _mode.mode == GameMode.gotcha ? int.parse(_goal) : (_mode.start ?? 501),
            mode: _mode.mode,
            doubleOut: _out == 'Double',
            legsToWin: _legs,
            cricketVariant: _mode.mode == GameMode.cricket ? _variant : CricketVariant.classic,
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
    if (_mode.mode == GameMode.cricket) return _cricketVariants[_variant]!.$2;
    if (_mode.mode == GameMode.gotcha) return 'Premier à $_goal pile. Si tu tombes sur le score d’un pote, il repart à 0.';
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
                  for (var r = 0; r < 3; r++)
                    Row(
                      spacing: Td.s2,
                      children: [
                        for (var c = 0; c < 4; c++)
                          Expanded(
                            child: r * 4 + c < _partyModes.length
                                ? _pill(_partyModes[r * 4 + c])
                                : const SizedBox.shrink(),
                          ),
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
              if (_mode.mode == GameMode.cricket) ...[
                const SizedBox(height: Td.s5),
                _label('Variante'),
                const SizedBox(height: Td.s3),
                Wrap(
                  spacing: Td.s2,
                  runSpacing: Td.s2,
                  children: [
                    for (final e in _cricketVariants.entries)
                      TdChip(label: e.value.$1, selected: e.key == _variant, onTap: () => setState(() => _variant = e.key)),
                  ],
                ),
              ],
              if (_mode.mode == GameMode.gotcha) ...[
                const SizedBox(height: Td.s5),
                _label('Score à atteindre'),
                const SizedBox(height: Td.s3),
                TdSegmented(
                  options: const ['201', '301', '501'],
                  value: _goal,
                  touch: true,
                  onChanged: (v) => setState(() => _goal = v),
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
              _label(_mode.mode == GameMode.cricket && _variant != CricketVariant.classic
                  ? 'Cricket ${_cricketVariants[_variant]!.$1}'
                  : _mode.title),
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

  Widget _board(_Mode m, {DartThrow? aimed}) {
    final heat = m.mode == GameMode.cricket && _variant == CricketVariant.tactic
        ? CricketGame.numbersFor(CricketVariant.tactic).toSet()
        : m.heat;
    return Dartboard(aimed: aimed ?? m.aimed, aimSector: m.aimSector, heat: heat, dim: heat.isEmpty);
  }

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
            SizedBox(
              width: 48,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(m.glyph, style: TdText.rounded(22, 900, on ? Td.sunset : Td.ink)),
              ),
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

  // MARK: Écran 2b, Choisis ton entraînement (familles Finir, Viser, Scorer, Robot)

  /// Record du jeu : (valeur, unité), "-" si jamais joué.
  (String, String) _recordOf(_Pick p, {String? opt}) {
    final o = opt ?? _opts[p.title] ?? p.opt;
    int? r;
    var unit = p.recUnit;
    switch (p.kind) {
      case _Kind.trainer:
        // Option du jeu demandé, pas forcément celui sélectionné.
        final option = switch (p.mode) {
          GameMode.nineDarts => int.parse(o ?? '121'),
          GameMode.randomCheckout => p.opts.indexOf(o ?? '61-110').clamp(0, 2),
          GameMode.darts99 => o == 'Bull' ? 25 : int.parse(o ?? '20'),
          GameMode.roundTheWorld => p.opts.indexOf(o ?? 'Simple') + 1,
          GameMode.countUp => int.parse(o ?? '8'),
          _ => 0,
        };
        r = trainerRecord(_shooter, p.mode!, option);
      case _Kind.drill:
        r = p.drill == _Drill.target ? practiceRecord(_shooter, target: _target, darts: _darts) : practiceRecord(_shooter);
        if (p.drill == _Drill.target) unit = 'sur $_darts au ${_target.label}';
      case _Kind.bot:
        r = _botBeaten(_shooter, p.mode);
      case _Kind.mode:
        r = null;
        unit = 'pas de record';
    }
    return (r == null ? '-' : '$r', unit);
  }

  Widget _practiceLayout() {
    final fam = _families[_fam]!;
    final picks = fam.$3;
    return Padding(
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
                _header(context, 'Choisis ton entraînement'),
                TdSegmented(
                  options: _families.keys.toList(),
                  value: _fam,
                  touch: true,
                  onChanged: (v) => setState(() => _fam = v),
                ),
                Text(fam.$2, style: TdText.inter(13, 18, 400, Td.ink3)),
                Expanded(
                  child: Column(
                    spacing: Td.s2,
                    children: [
                      for (var r = 0; r < 2; r++)
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            spacing: Td.s2,
                            children: [
                              for (var c = 0; c < 3; c++)
                                Expanded(
                                  child: r * 3 + c < picks.length ? _tile(r * 3 + c, picks[r * 3 + c]) : const SizedBox.shrink(),
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
          Container(
            width: 320,
            padding: const EdgeInsets.all(Td.s4),
            decoration: _glass(),
            child: _practicePanel(fam.$1),
          ),
        ],
      ),
    );
  }

  Widget _tile(int i, _Pick p) {
    final (v, u) = _recordOf(p);
    final rec = p.kind == _Kind.mode || v == '-' ? '' : (p.kind == _Kind.bot ? ' Battu au $v.' : ' Record $v.');
    return ModeTile(
      glyph: p.glyph,
      title: p.title,
      desc: '${p.desc}$rec',
      selected: _sel[_fam] == i,
      onTap: () => setState(() => _sel[_fam] = i),
    );
  }

  Widget _practicePanel(String famName) {
    final p = _pick;
    final (rv, ru) = _recordOf(p);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Td.s3,
      children: [
        _label(famName),
        Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TdText.inter(22, 28, 700, Td.ink)),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Td.s3,
              children: [
                Text(p.rule, style: TdText.inter(15, 20, 400, Td.ink2)),
                if (p.kind == _Kind.bot)
                  Text(
                    rv == '-' ? 'Pas encore battu.' : 'Ton record : battu au $rv.',
                    style: TdText.inter(13, 18, 400, Td.ink3),
                  )
                else if (p.kind != _Kind.mode)
                  KpiTile(label: 'Ton record', value: rv, unit: ru),
                if (p.drill == _Drill.target) ...[
                  _label('Cible'),
                  Wrap(
                    spacing: Td.s2,
                    runSpacing: Td.s2,
                    children: [
                      for (final t in TrainingTarget.presets)
                        TdChip(label: t.label, selected: t == _target, onTap: () => setState(() => _target = t)),
                    ],
                  ),
                  _label('Fléchettes'),
                  TdSegmented(
                    options: const ['9', '15', '30'],
                    value: '$_darts',
                    touch: true,
                    height: 52,
                    onChanged: (v) => setState(() => _darts = int.parse(v)),
                  ),
                ],
                if (p.optLabel != null) ...[
                  _label(p.kind == _Kind.bot ? '${p.optLabel!} · ${BotLevel.of(int.parse(_opt ?? '60')).name}' : p.optLabel!),
                  TdSegmented(
                    options: p.opts,
                    value: _opt ?? p.opts.first,
                    touch: true,
                    height: 52,
                    onChanged: (v) => setState(() => _opts[p.title] = v),
                  ),
                ],
                if (p.kind == _Kind.bot) ...[
                  _label('Qui commence'),
                  TdSegmented(
                    options: const ['Toi', 'Le robot'],
                    value: _botFirst,
                    touch: true,
                    height: 52,
                    onChanged: (v) => setState(() => _botFirst = v),
                  ),
                ],
                if (_everyone.length > 1) ...[
                  _label('Qui tire'),
                  Wrap(
                    spacing: Td.s2,
                    runSpacing: Td.s2,
                    children: [
                      for (final n in _everyone)
                        TdChip(label: n, icon: LucideIcons.user, selected: n == _shooter, onTap: () => _toggle(n)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        TdButton(label: 'Lancer', icon: LucideIcons.play, onPressed: _launch),
      ],
    );
  }
}
