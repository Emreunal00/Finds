import Foundation
import FirebaseFirestore

struct WatchedEntry: Codable, Equatable {
    let id: Int
    let type: String // "movie" or "tv"
}

struct Profile: Codable, Identifiable, Equatable {
    var id: String // e.g. UUID string
    var displayName: String?
    var photoURL: String?
    var createdAt: Date
    var watchedEntries: [WatchedEntry]
    var favoritesEntries: [WatchedEntry]
    var watchlistEntries: [WatchedEntry]
    // You may add more profile-specific fields as needed
    
    init(id: String = UUID().uuidString,
         displayName: String? = nil,
         photoURL: String? = nil,
         createdAt: Date = Date(),
         watchedEntries: [WatchedEntry] = [],
         favoritesEntries: [WatchedEntry] = [],
         watchlistEntries: [WatchedEntry] = []) {
        self.id = id
        self.displayName = displayName
        self.photoURL = photoURL
        self.createdAt = createdAt
        self.watchedEntries = watchedEntries
        self.favoritesEntries = favoritesEntries
        self.watchlistEntries = watchlistEntries
    }
}

struct UserProfile: Codable, Identifiable, Equatable {
    var id: String?
    var email: String
    
    // Legacy simple ID lists (deprecated, for backward compatibility)
    var watchlistIDs: [Int]
    var watchedIDs: [Int]            // legacy support
    var favoritesIDs: [Int]
    
    // New profiles array
    var profiles: [Profile]
    var selectedProfileID: String? // currently active profile ID, optional

    init(id: String? = nil,
         email: String,
         watchlistIDs: [Int] = [],
         watchedIDs: [Int] = [],
         favoritesIDs: [Int] = [],
         profiles: [Profile] = [],
         selectedProfileID: String? = nil) {
        self.id = id
        self.email = email
        self.watchlistIDs = watchlistIDs
        self.watchedIDs = watchedIDs
        self.favoritesIDs = favoritesIDs
        self.profiles = profiles
        self.selectedProfileID = selectedProfileID
    }
}

extension UserProfile {
    static func empty(uid: String, email: String) -> UserProfile {
        UserProfile(id: uid,
                    email: email,
                    watchlistIDs: [],
                    watchedIDs: [],
                    favoritesIDs: [],
                    profiles: [],
                    selectedProfileID: nil)
    }
}

final class UserProfileRepository {
    private let db = Firestore.firestore()
    private var users: CollectionReference { db.collection("users") }

    func createOrMerge(_ profile: UserProfile) async throws {
        guard let uid = profile.id else {
            throw NSError(domain: "UserProfile", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing uid"])
        }

        let createdAtTimestamp = Timestamp(date: Date())

        // Convert profiles array to array of dictionaries for Firestore
        let profilesData: [[String: Any]] = profile.profiles.map { prof in
            [
                "id": prof.id,
                "displayName": prof.displayName as Any,
                "photoURL": prof.photoURL as Any,
                "createdAt": Timestamp(date: prof.createdAt),
                "watchedEntries": prof.watchedEntries.map { ["id": $0.id, "type": $0.type] },
                "favoritesEntries": prof.favoritesEntries.map { ["id": $0.id, "type": $0.type] },
                "watchlistEntries": prof.watchlistEntries.map { ["id": $0.id, "type": $0.type] }
            ]
        }

        let data: [String: Any] = [
            "email": profile.email,
            // Legacy fields retained for backward-compatibility (deprecated)
            "watchlistIDs": profile.watchlistIDs,
            "watchedIDs": profile.watchedIDs,
            "favoritesIDs": profile.favoritesIDs,
            // New profiles array with all profile-specific fields nested inside
            "profiles": profilesData,
            "selectedProfileID": profile.selectedProfileID as Any,
            "createdAt": createdAtTimestamp
        ].merging(optional: [:]) // no optional fields at root

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            users.document(uid).setData(data, merge: true) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func fetch(uid: String) async throws -> UserProfile {
        let snapshot = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<DocumentSnapshot, Error>) in
            users.document(uid).getDocument { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let snapshot {
                    continuation.resume(returning: snapshot)
                } else {
                    continuation.resume(throwing: NSError(domain: "UserProfile", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown Firestore error"]))
                }
            }
        }

        return try decode(snapshot: snapshot)
    }

    func decode(snapshot: DocumentSnapshot) throws -> UserProfile {
        guard snapshot.exists, let dict = snapshot.data() else {
            throw NSError(domain: "UserProfile", code: 1, userInfo: [NSLocalizedDescriptionKey: "User profile not found"])
        }

        let email = dict["email"] as? String ?? ""

        // Legacy simple ID lists (deprecated, for backward compatibility)
        let watchlistIDs = ints(from: dict["watchlistIDs"])
        let watchedIDs = ints(from: dict["watchedIDs"])
        let favoritesIDs = ints(from: dict["favoritesIDs"])

        // Parse profiles array if present
        var profiles: [Profile] = []
        if let profilesArr = dict["profiles"] as? [[String: Any]], !profilesArr.isEmpty {
            profiles = profilesArr.compactMap { pDict in
                guard let id = pDict["id"] as? String else { return nil }
                let displayName = pDict["displayName"] as? String
                let photoURL = pDict["photoURL"] as? String

                let createdAtDate: Date = {
                    if let ts = pDict["createdAt"] as? Timestamp {
                        return ts.dateValue()
                    } else if let date = pDict["createdAt"] as? Date {
                        return date
                    } else {
                        return Date(timeIntervalSince1970: 0)
                    }
                }()

                func entries(from any: Any?) -> [WatchedEntry] {
                    if let arr = any as? [[String: Any]] {
                        return arr.compactMap { m in
                            if let id = m["id"] as? Int, let type = m["type"] as? String {
                                return WatchedEntry(id: id, type: type)
                            } else if let idNum = m["id"] as? NSNumber, let type = m["type"] as? String {
                                return WatchedEntry(id: idNum.intValue, type: type)
                            }
                            return nil
                        }
                    }
                    return []
                }

                let watchedEntries = entries(from: pDict["watchedEntries"])
                let favoritesEntries = entries(from: pDict["favoritesEntries"])
                let watchlistEntries = entries(from: pDict["watchlistEntries"])

                return Profile(
                    id: id,
                    displayName: displayName,
                    photoURL: photoURL,
                    createdAt: createdAtDate,
                    watchedEntries: watchedEntries,
                    favoritesEntries: favoritesEntries,
                    watchlistEntries: watchlistEntries
                )
            }
        } else {
            // No profiles array found, build a single profile from legacy single profile fields (deprecated)
            // Use the root-level fields like displayName, photoURL, watchedEntries, etc. for backward compatibility if they existed,
            // but these are removed from UserProfile and moved to Profile, so we create a Profile here with legacy ID "default"
            let displayName = dict["displayName"] as? String
            let photoURL = dict["photoURL"] as? String

            func entries(from any: Any?) -> [WatchedEntry] {
                if let arr = any as? [[String: Any]] {
                    return arr.compactMap { m in
                        if let id = m["id"] as? Int, let type = m["type"] as? String {
                            return WatchedEntry(id: id, type: type)
                        } else if let idNum = m["id"] as? NSNumber, let type = m["type"] as? String {
                            return WatchedEntry(id: idNum.intValue, type: type)
                        }
                        return nil
                    }
                }
                return []
            }

            let watchedEntries: [WatchedEntry] = {
                let typed = entries(from: dict["watchedEntries"])
                if !typed.isEmpty { return typed }
                if !watchedIDs.isEmpty {
                    return watchedIDs.map { WatchedEntry(id: $0, type: "movie") }
                }
                return []
            }()

            let favoritesEntries: [WatchedEntry] = {
                let typed = entries(from: dict["favoritesEntries"])
                if !typed.isEmpty { return typed }
                if !favoritesIDs.isEmpty {
                    return favoritesIDs.map { WatchedEntry(id: $0, type: "movie") }
                }
                return []
            }()

            let watchlistEntries: [WatchedEntry] = {
                let typed = entries(from: dict["watchlistEntries"])
                if !typed.isEmpty { return typed }
                if !watchlistIDs.isEmpty {
                    return watchlistIDs.map { WatchedEntry(id: $0, type: "movie") }
                }
                return []
            }()

            let createdAtDate: Date = {
                if let ts = dict["createdAt"] as? Timestamp {
                    return ts.dateValue()
                } else if let date = dict["createdAt"] as? Date {
                    return date
                } else {
                    return Date(timeIntervalSince1970: 0)
                }
            }()

            let singleProfile = Profile(
                id: "default",
                displayName: displayName,
                photoURL: photoURL,
                createdAt: createdAtDate,
                watchedEntries: watchedEntries,
                favoritesEntries: favoritesEntries,
                watchlistEntries: watchlistEntries
            )
            profiles = [singleProfile]
        }

        let selectedProfileID = dict["selectedProfileID"] as? String

        return UserProfile(
            id: snapshot.documentID,
            email: email,
            watchlistIDs: watchlistIDs,
            watchedIDs: watchedIDs,
            favoritesIDs: favoritesIDs,
            profiles: profiles,
            selectedProfileID: selectedProfileID
        )
    }

    // MARK: - Array field helpers

    private func updateArrayField(uid: String, field: String, add values: [Any]? = nil, remove valuesToRemove: [Any]? = nil) async throws {
        var update: [String: Any] = [:]
        if let values { update[field] = FieldValue.arrayUnion(values) }
        if let valuesToRemove { update[field] = FieldValue.arrayRemove(valuesToRemove) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            users.document(uid).updateData(update) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    // Favorites (legacy)
    func addToFavorites(uid: String, id: Int) async throws {
        try await updateArrayField(uid: uid, field: "favoritesIDs", add: [id])
    }
    func removeFromFavorites(uid: String, id: Int) async throws {
        try await updateArrayField(uid: uid, field: "favoritesIDs", remove: [id])
    }

    // Watchlist (legacy)
    func addToWatchlist(uid: String, id: Int) async throws {
        try await updateArrayField(uid: uid, field: "watchlistIDs", add: [id])
    }
    func removeFromWatchlist(uid: String, id: Int) async throws {
        try await updateArrayField(uid: uid, field: "watchlistIDs", remove: [id])
    }

    // Watched (typed)
    func addToWatched(uid: String, entry: WatchedEntry) async throws {
        try await updateArrayField(uid: uid, field: "watchedEntries", add: [["id": entry.id, "type": entry.type]])
    }
    func removeFromWatched(uid: String, entry: WatchedEntry) async throws {
        try await updateArrayField(uid: uid, field: "watchedEntries", remove: [["id": entry.id, "type": entry.type]])
    }

    // Favorites (typed)
    func addToFavorites(uid: String, entry: WatchedEntry) async throws {
        try await updateArrayField(uid: uid, field: "favoritesEntries", add: [["id": entry.id, "type": entry.type]])
    }
    func removeFromFavorites(uid: String, entry: WatchedEntry) async throws {
        try await updateArrayField(uid: uid, field: "favoritesEntries", remove: [["id": entry.id, "type": entry.type]])
    }

    // Watchlist (typed)
    func addToWatchlist(uid: String, entry: WatchedEntry) async throws {
        try await updateArrayField(uid: uid, field: "watchlistEntries", add: [["id": entry.id, "type": entry.type]])
    }
    func removeFromWatchlist(uid: String, entry: WatchedEntry) async throws {
        try await updateArrayField(uid: uid, field: "watchlistEntries", remove: [["id": entry.id, "type": entry.type]])
    }

    // Backward-compat (not used after migration, but keep)
    func addToWatched(uid: String, id: Int) async throws {
        try await updateArrayField(uid: uid, field: "watchedIDs", add: [id])
    }
    func removeFromWatched(uid: String, id: Int) async throws {
        try await updateArrayField(uid: uid, field: "watchedIDs", remove: [id])
    }

    // Utility functions for parsing ints from mixed types
    private func ints(from any: Any?) -> [Int] {
        if let arr = any as? [Int] { return arr }
        if let arr = any as? [String] {
            return arr.compactMap { Int($0.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) }
        }
        if let arr = any as? [NSNumber] { return arr.map { $0.intValue } }
        return []
    }
}

private extension Dictionary where Key == String, Value == Any {
    func merging(optional: [String: Any?]) -> [String: Any] {
        var result = self
        for (k, v) in optional {
            if let v { result[k] = v }
        }
        return result
    }
}
