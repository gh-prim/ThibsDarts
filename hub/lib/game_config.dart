import 'setup/owner_store.dart';

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

/// État de l'appareil, en mémoire en attendant SQLite.
class AppState {
  AppState._();

  /// Compte propriétaire, créé au setup depuis l'iPhone. Seul joueur connu au départ.
  static String owner = 'Thibs';

  /// Profil complet du propriétaire (photo comprise), null tant que le setup n'est pas fait.
  static Owner? ownerProfile;

  static void setOwner(Owner o) {
    ownerProfile = o;
    owner = o.nickname.isEmpty ? o.firstName : o.nickname;
  }

  /// Dernière partie lancée, pour "Rejouer".
  static GameConfig? lastGame;

  /// Résumé de la dernière partie terminée ("Thibs a gagné en 18 fléchettes.").
  static String? lastResult;
}
