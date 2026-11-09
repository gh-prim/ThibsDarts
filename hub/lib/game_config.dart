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
    GameMode.cricket => 'Cricket',
    GameMode.clock => 'Around the clock',
    GameMode.shanghai => 'Shanghai',
    GameMode.killer => 'Killer',
    GameMode.halveIt => 'Halve-it',
    GameMode.bobs27 => "Bob's 27",
  };

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
