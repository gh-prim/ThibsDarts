import 'package:darts_engine/darts_engine.dart';

import 'setup/owner_store.dart';

/// Réglages d'une partie, choisis sur "Nouvelle partie". Sans [mode], c'est un X01.
class GameConfig {
  const GameConfig({
    required this.players,
    this.startScore = 501,
    this.doubleOut = true,
    this.legsToWin = 1,
    this.mode,
    this.tournamentMatch,
    this.training,
    this.trainingDarts = 15,
    this.freeVolleys,
    this.practice = false,
    this.cricketVariant = CricketVariant.classic,
    this.botLevel,
    this.option = 0,
  });

  final List<String> players;
  final GameMode? mode;
  final int startScore;
  final bool doubleOut;
  final int legsToWin;

  /// Match de tournoi joué par cette partie : le résultat remonte au tableau.
  final String? tournamentMatch;

  /// Série libre en solo sur cette cible (planche Entraînement). Prioritaire sur [mode].
  final TrainingTarget? training;

  /// Fléchettes dans la série.
  final int trainingDarts;

  /// Volées libres de 3 : nombre de volées, 0 pour sans fin. Prioritaire sur [mode].
  final int? freeVolleys;

  /// Partie d'entraînement en solo : sans salon, hors des parties gagnées ou perdues.
  final bool practice;

  /// Variante du Cricket (No Score, Cut-Throat, Random, Tactic).
  final CricketVariant cricketVariant;

  /// Robot adversaire : sa moyenne (30 à 105), null sans robot.
  final int? botLevel;

  /// Réglage propre au jeu : départ (9 Darts : 121 ou 81), plage (Checkout au hasard),
  /// cible (99 fléchettes), segment (Tour du monde : 1, 2, 3), volées (Count Up).
  final int option;

  /// Nom du robot dans la partie.
  static const botName = 'Robot';

  bool get hasBot => botLevel != null;

  /// Écran d'entraînement dédié (série sur cible ou volées libres).
  bool get drill => training != null || freeVolleys != null;

  String get label => training != null
      ? 'série ${training!.label} de $trainingDarts fléchettes'
      : freeVolleys != null
      ? (freeVolleys == 0 ? 'volées libres' : '$freeVolleys volées libres')
      : mode == null ? '$startScore ${doubleOut ? 'double out' : 'single out'}' : title;

  /// Nom du jeu : "501", "Cricket"...
  String get title => drill ? 'Entraînement' : switch (mode) {
    null => '$startScore',
    GameMode.cricket => switch (cricketVariant) {
      CricketVariant.classic => 'Cricket',
      CricketVariant.noScore => 'Cricket No Score',
      CricketVariant.cutThroat => 'Cricket Cut-Throat',
      CricketVariant.random => 'Cricket Random',
      CricketVariant.tactic => 'Cricket Tactic',
    },
    GameMode.clock => 'Around the clock',
    GameMode.shanghai => 'Shanghai',
    GameMode.killer => 'Killer',
    GameMode.halveIt => 'Halve-it',
    GameMode.bobs27 => "Bob's 27",
    GameMode.bermuda => 'Bermuda',
    GameMode.gotcha => 'Gotcha',
    GameMode.catch40 => 'Catch 40',
    GameMode.nineDarts => '9 Darts Double Out',
    GameMode.randomCheckout => 'Checkout au hasard',
    GameMode.ton70 => '170',
    GameMode.fortyOne => '41-60',
    GameMode.jdc => 'JDC Challenge',
    GameMode.darts99 => '99 fléchettes',
    GameMode.roundTheWorld => 'Tour du monde',
    GameMode.countUp => 'Count Up',
    GameMode.cricketCountUp => 'Cricket Count Up',
  };

  /// Ligne du salon : "Cricket · 20 à 15 et bull".
  String get subtitle {
    final m = mode;
    if (m == null) {
      final out = doubleOut ? 'Double sortie' : 'Sortie simple';
      final legs = legsToWin == 1 ? '1 manche' : '$legsToWin manches gagnantes';
      return '$startScore · $out · $legs';
    }
    final rule = switch (m) {
      GameMode.cricket => switch (cricketVariant) {
        CricketVariant.classic => '20 à 15 et bull',
        CricketVariant.noScore => 'Fermer seulement',
        CricketVariant.cutThroat => 'Les points vont aux autres',
        CricketVariant.random => '6 numéros au hasard',
        CricketVariant.tactic => '20 à 10 et bull',
      },
      GameMode.clock => 'De 1 à 20',
      GameMode.shanghai => '7 manches',
      GameMode.killer => '3 vies',
      GameMode.halveIt => '9 manches',
      GameMode.bobs27 => 'D1 à D20 puis bull',
      GameMode.bermuda => '12 manches, raté divise par deux',
      GameMode.gotcha => '301 pile',
      _ => 'Entraînement',
    };
    return '$title · $rule';
  }

  GameConfig withPlayers(List<String> names) => GameConfig(
    players: names,
    startScore: startScore,
    doubleOut: doubleOut,
    legsToWin: legsToWin,
    mode: mode,
    tournamentMatch: tournamentMatch,
    training: training,
    trainingDarts: trainingDarts,
    freeVolleys: freeVolleys,
    practice: practice,
    cricketVariant: cricketVariant,
    botLevel: botLevel,
    option: option,
  );

  /// Même partie avec un autre niveau de robot (fin de partie : monter ou descendre).
  GameConfig withBot(int level) => GameConfig(
    players: players,
    startScore: startScore,
    doubleOut: doubleOut,
    legsToWin: legsToWin,
    mode: mode,
    training: training,
    trainingDarts: trainingDarts,
    freeVolleys: freeVolleys,
    practice: practice,
    cricketVariant: cricketVariant,
    botLevel: level,
    option: option,
  );
}

/// État de l'appareil, en mémoire en attendant SQLite.
class AppState {
  AppState._();

  /// Compte propriétaire, créé au setup depuis l'iPhone. Seul joueur connu au départ.
  static String owner = 'Thibs';

  /// Profil complet du propriétaire (photo comprise), null tant que le setup n'est pas fait.
  static Owner? ownerProfile;

  /// Photos de profil par nom de joueur (propriétaire et potes venus avec leur iPhone).
  static final Map<String, String> photos = {};

  static void setOwner(Owner o) {
    ownerProfile = o;
    owner = o.nickname.isEmpty ? o.firstName : o.nickname;
    if (o.photoPath != null) photos[owner] = o.photoPath!;
  }

  /// Dernière partie lancée, pour "Rejouer".
  static GameConfig? lastGame;

  /// Résumé de la dernière partie terminée ("Thibs a gagné en 18 fléchettes.").
  static String? lastResult;
}
