import PerryObjCInterop

/// GKErrorDomain's codes: the player is not signed in to Game Center.
enum GameErrors {
    static let domain = "GKErrorDomain"
    static let notAuthenticated = 6

    static func make(_ code: Int) -> NSError { NSError.make(domain: domain, code: code, userInfo: nil) }
}

/// Completion handlers, called later on the main queue as GameKit's are.
enum Completion {
    /// A handler given only an error (`^(NSError *error)`).
    static func fail(_ handler: ObjCBlock?) {
        guard let handler else { return }
        Dispatch.onMain {
            handler.function(as: (@convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?) -> Void).self)(
                handler.object, GameErrors.make(GameErrors.notAuthenticated).objcObject)
        }
    }

    /// A handler given what was loaded, here nothing, and an error
    /// (`^(NSArray *objects, NSError *error)`).
    static func failLoading(_ handler: ObjCBlock?) {
        guard let handler else { return }
        Dispatch.onMain {
            handler.function(as: (@convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?,
                                                  UnsafeMutableRawPointer?) -> Void).self)(
                handler.object, nil, GameErrors.make(GameErrors.notAuthenticated).objcObject)
        }
    }
}

// MARK: - Players

@ObjCClass("GKBasePlayer")
open class GKBasePlayer: NSObject {
    @ObjCMethod("playerID") func playerID() -> String? { nil }
    @ObjCMethod("displayName") func displayName() -> String? { nil }
}

@ObjCClass("GKPlayer")
open class GKPlayer: GKBasePlayer {
    @ObjCMethod("alias") func alias() -> String? { nil }
    @ObjCMethod("gamePlayerID") func gamePlayerID() -> String? { nil }
    @ObjCMethod("teamPlayerID") func teamPlayerID() -> String? { nil }
    @ObjCMethod("isInvitable") func isInvitable() -> Bool { false }
    @ObjCMethod("scopedIDsArePersistent") func scopedIDsArePersistent() -> Bool { false }
}

/// The local player, never signed in: the sign-in handler is kept and
/// never called, as on a device whose Game Center sign-in is still to
/// come, so a game neither shows a sign-in screen nor reports an error.
@ObjCClass("GKLocalPlayer")
open class GKLocalPlayer: GKPlayer {
    nonisolated(unsafe) static var shared: GKLocalPlayer?
    var handler: ObjCBlock?

    @ObjCClassMethod("localPlayer")
    static func localPlayer() -> GKLocalPlayer {
        if let shared { return shared }
        let player = GKLocalPlayer()
        shared = player
        return player
    }

    @ObjCClassMethod("local") static func local() -> GKLocalPlayer { localPlayer() }

    @ObjCMethod("isAuthenticated") func isAuthenticated() -> Bool { false }
    @ObjCMethod("isUnderage") func isUnderage() -> Bool { false }
    @ObjCMethod("isMultiplayerGamingRestricted") func isMultiplayerGamingRestricted() -> Bool { true }
    @ObjCMethod("isPersonalizedCommunicationRestricted") func isPersonalizedCommunicationRestricted() -> Bool { true }
    @ObjCMethod("authenticateHandler") func authenticateHandler() -> ObjCBlock? { handler }
    @ObjCMethod("setAuthenticateHandler:") func setAuthenticateHandler(_ handler: ObjCBlock?) { self.handler = handler }
    @ObjCMethod("authenticateWithCompletionHandler:") func authenticate(completionHandler: ObjCBlock?) {}
    @ObjCMethod("registerListener:") func registerListener(_ listener: NSObject?) {}
    @ObjCMethod("unregisterListener:") func unregisterListener(_ listener: NSObject?) {}
    @ObjCMethod("unregisterAllListeners") func unregisterAllListeners() {}
    @ObjCMethod("loadFriendPlayersWithCompletionHandler:") func loadFriendPlayers(completionHandler: ObjCBlock?) {
        Completion.failLoading(completionHandler)
    }
    @ObjCMethod("loadFriendsWithCompletionHandler:") func loadFriends(completionHandler: ObjCBlock?) {
        Completion.failLoading(completionHandler)
    }
    @ObjCMethod("loadDefaultLeaderboardIdentifierWithCompletionHandler:")
    func loadDefaultLeaderboardIdentifier(completionHandler: ObjCBlock?) { Completion.failLoading(completionHandler) }
    @ObjCMethod("setDefaultLeaderboardIdentifier:completionHandler:")
    func setDefaultLeaderboardIdentifier(_ identifier: String?, completionHandler: ObjCBlock?) { Completion.fail(completionHandler) }
}

// MARK: - Scores

/// A score, which reporting sends nowhere.
@ObjCClass("GKScore")
open class GKScore: NSObject {
    var leaderboard: String?
    var amount: Int64 = 0
    var contextValue: UInt64 = 0
    var setsDefault = false

    @ObjCMethod("initWithLeaderboardIdentifier:")
    func initialize(leaderboardIdentifier: String?) -> Self {
        leaderboard = leaderboardIdentifier
        return self
    }

    @ObjCMethod("initWithLeaderboardIdentifier:player:")
    func initialize(leaderboardIdentifier: String?, player: NSObject?) -> Self {
        leaderboard = leaderboardIdentifier
        return self
    }

    @ObjCMethod("initWithLeaderboardIdentifier:forPlayer:")
    func initialize(leaderboardIdentifier: String?, forPlayer: String?) -> Self {
        leaderboard = leaderboardIdentifier
        return self
    }

    @ObjCMethod("initWithCategory:")
    func initialize(category: String?) -> Self {
        leaderboard = category
        return self
    }

    @ObjCMethod("leaderboardIdentifier") func leaderboardIdentifier() -> String? { leaderboard }
    @ObjCMethod("setLeaderboardIdentifier:") func setLeaderboardIdentifier(_ value: String?) { leaderboard = value }
    @ObjCMethod("category") func category() -> String? { leaderboard }
    @ObjCMethod("setCategory:") func setCategory(_ value: String?) { leaderboard = value }
    @ObjCMethod("value") func value() -> Int64 { amount }
    @ObjCMethod("setValue:") func setValue(_ value: Int64) { amount = value }
    @ObjCMethod("context") func context() -> UInt64 { contextValue }
    @ObjCMethod("setContext:") func setContext(_ value: UInt64) { contextValue = value }
    @ObjCMethod("shouldSetDefaultLeaderboard") func shouldSetDefaultLeaderboard() -> Bool { setsDefault }
    @ObjCMethod("setShouldSetDefaultLeaderboard:") func setShouldSetDefaultLeaderboard(_ value: Bool) { setsDefault = value }
    @ObjCMethod("formattedValue") func formattedValue() -> String? { String(amount) }
    @ObjCMethod("rank") func rank() -> Int { 0 }
    @ObjCMethod("player") func player() -> NSObject? { nil }
    @ObjCMethod("playerID") func playerID() -> String? { nil }
    @ObjCMethod("date") func date() -> NSObject? { nil }

    @ObjCClassMethod("reportScores:withCompletionHandler:")
    static func reportScores(_ scores: NSObject?, completionHandler: ObjCBlock?) { Completion.fail(completionHandler) }

    @ObjCClassMethod("reportScores:withEligibleChallenges:withCompletionHandler:")
    static func reportScores(_ scores: NSObject?, eligibleChallenges: NSObject?, completionHandler: ObjCBlock?) {
        Completion.fail(completionHandler)
    }

    @ObjCMethod("reportScoreWithCompletionHandler:")
    func reportScore(completionHandler: ObjCBlock?) { Completion.fail(completionHandler) }
}

// MARK: - Achievements

/// An achievement, which reporting sends nowhere and loading never finds.
@ObjCClass("GKAchievement")
open class GKAchievement: NSObject {
    var identifierValue: String?
    var percent: Double = 0
    var showsBanner = false

    @ObjCMethod("initWithIdentifier:")
    func initialize(identifier: String?) -> Self {
        identifierValue = identifier
        return self
    }

    @ObjCMethod("initWithIdentifier:player:")
    func initialize(identifier: String?, player: NSObject?) -> Self {
        identifierValue = identifier
        return self
    }

    @ObjCMethod("identifier") func identifier() -> String? { identifierValue }
    @ObjCMethod("setIdentifier:") func setIdentifier(_ value: String?) { identifierValue = value }
    @ObjCMethod("percentComplete") func percentComplete() -> Double { percent }
    @ObjCMethod("setPercentComplete:") func setPercentComplete(_ value: Double) { percent = value }
    @ObjCMethod("isCompleted") func isCompleted() -> Bool { percent >= 100 }
    @ObjCMethod("showsCompletionBanner") func showsCompletionBanner() -> Bool { showsBanner }
    @ObjCMethod("setShowsCompletionBanner:") func setShowsCompletionBanner(_ value: Bool) { showsBanner = value }
    @ObjCMethod("lastReportedDate") func lastReportedDate() -> NSObject? { nil }
    @ObjCMethod("player") func player() -> NSObject? { nil }

    @ObjCClassMethod("reportAchievements:withCompletionHandler:")
    static func reportAchievements(_ achievements: NSObject?, completionHandler: ObjCBlock?) { Completion.fail(completionHandler) }

    @ObjCClassMethod("reportAchievements:withEligibleChallenges:withCompletionHandler:")
    static func reportAchievements(_ achievements: NSObject?, eligibleChallenges: NSObject?, completionHandler: ObjCBlock?) {
        Completion.fail(completionHandler)
    }

    @ObjCClassMethod("loadAchievementsWithCompletionHandler:")
    static func loadAchievements(completionHandler: ObjCBlock?) { Completion.failLoading(completionHandler) }

    @ObjCClassMethod("resetAchievementsWithCompletionHandler:")
    static func resetAchievements(completionHandler: ObjCBlock?) { Completion.fail(completionHandler) }

    @ObjCMethod("reportAchievementWithCompletionHandler:")
    func reportAchievement(completionHandler: ObjCBlock?) { Completion.fail(completionHandler) }
}

// MARK: - Challenges

/// Challenges, which no one sends.
@ObjCClass("GKChallenge")
open class GKChallenge: NSObject {
    @ObjCClassMethod("loadReceivedChallengesWithCompletionHandler:")
    static func loadReceivedChallenges(completionHandler: ObjCBlock?) { Completion.failLoading(completionHandler) }

    @ObjCMethod("decline") func decline() {}
    @ObjCMethod("state") func state() -> Int { 0 }
    @ObjCMethod("message") func message() -> String? { nil }
    @ObjCMethod("issuingPlayer") func issuingPlayer() -> NSObject? { nil }
    @ObjCMethod("receivingPlayer") func receivingPlayer() -> NSObject? { nil }
}

@ObjCClass("GKScoreChallenge")
open class GKScoreChallenge: GKChallenge {
    @ObjCMethod("score") func score() -> NSObject? { nil }
}

@ObjCClass("GKAchievementChallenge")
open class GKAchievementChallenge: GKChallenge {
    @ObjCMethod("achievement") func achievement() -> NSObject? { nil }
}

// MARK: - Constants

@ObjCConstants
enum GameConstants {
    static let GKErrorDomain = "GKErrorDomain"
    static let GKPlayerAuthenticationDidChangeNotificationName = "GKPlayerAuthenticationDidChangeNotificationName"
    static let GKPlayerDidChangeNotificationName = "GKPlayerDidChangeNotificationName"
}
