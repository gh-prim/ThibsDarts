import Foundation

// Tournoi du Pi, partagé entre l'app iPhone et l'app Apple TV.

struct TournamentPlayer: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let photo: Bool

    func photoURL(base: URL) -> URL? {
        photo ? base.appendingPathComponent("api/players/\(id)/photo") : nil
    }
}

struct TournamentMatch: Decodable, Identifiable, Hashable {
    let id: String
    let a: TournamentPlayer?
    let b: TournamentPlayer?
    let scoreA: Int
    let scoreB: Int
    let winner: String?
    /// attente, pret, direct, fini ou gratuit (place vide au tirage).
    let state: String
}

struct TournamentRound: Decodable, Hashable {
    /// "8es", "Quarts", "Demies", "Finale".
    let name: String
    /// "8e de finale", "Demi-finale".
    let title: String
    let matches: [TournamentMatch]
}

struct TournamentInfo: Decodable, Equatable {
    let id: String
    let name: String
    let organizer: String
    let mode: String
    let legsToWin: Int
    /// inscriptions, tirage, en_cours, fini.
    let state: String
    let size: Int
    let max: Int
    let entrants: [TournamentPlayer]
    let rounds: [TournamentRound]
    let next: String?
    let champion: TournamentPlayer?

    var modeLabel: String { mode == "cricket" ? "Cricket" : mode }
    var legsLabel: String { legsToWin == 1 ? "1 manche" : "\(legsToWin) manches gagnantes" }
    /// "16 joueurs · 501 · 3 manches gagnantes".
    var summary: String { "\(entrants.count) joueurs · \(modeLabel) · \(legsLabel)" }
}

extension LobbyAPI {
    static func tournament(at base: URL) async throws -> TournamentInfo? {
        struct Reply: Decodable { let tournament: TournamentInfo? }
        guard let (data, res) = try? await session.data(from: base.appendingPathComponent("api/tournament")),
              (res as? HTTPURLResponse)?.statusCode == 200 else { throw PiError.unreachable }
        return try JSONDecoder().decode(Reply.self, from: data).tournament
    }
}
