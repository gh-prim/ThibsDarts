/// Réglages d'une partie X01, choisis sur "Nouvelle partie".
class GameConfig {
  const GameConfig({
    required this.players,
    this.startScore = 501,
    this.doubleOut = true,
    this.legsToWin = 1,
  });

  final List<String> players;
  final int startScore;
  final bool doubleOut;
  final int legsToWin;

  String get label => '$startScore ${doubleOut ? 'double out' : 'single out'}';
}

/// Joueurs connus en attendant les profils (SQLite + iPhone).
const knownPlayers = ['Thibs', 'Max', 'Inès', 'Léo'];

/// Moyennes de démo.
const demoAverages = {'Thibs': 62.4, 'Max': 48.1, 'Inès': 41.7, 'Léo': 39.2};
