import ActivityKit
import Foundation

@available(iOS 16.2, *)
struct UnourTableAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var round: Int
        var phase: String
        var spectator: Bool
        var turnName: String
        var isYourTurn: Bool
        var myCount: Int
        var topCard: String
        var symbol: String
        var activeColor: String
        var pendingDraw: Int
        var direction: Int
        var players: String
        var connected: Bool
        var updatedAt: Double
    }

    var roomId: String
    var spectator: Bool
}
