import Foundation
import FirebaseFirestore

struct WatchedEntry: Codable, Equatable {
    let id: Int
    let type: String // "movie" or "tv"
}

struct UserProfile: Codable, Identifiable, Equatable {
    var id: String?
    var email: String
    var displayName: String?
    var photoURL: String?
    var createdAt: Date
    var watchlistIDs: [Int]
    var watchedIDs: [Int]            // legacy support
    var favoritesIDs: [Int]
    // NEW: typed watched entries
    var watchedEntries: [WatchedEntry]

    init(id: String? = nil,
         email: String,
         displayName: String? = nil,
         photoURL: String? = nil,
         createdAt: Date = Date(),
         watchlistIDs: [Int] = [],
         watchedIDs: [Int] = [],
         favoritesIDs: [Int] = [],
         watchedEntries: [WatchedEntry] = []) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.photoURL = photoURL
        self.createdAt = createdAt
        self.watchlistIDs = watchlistIDs
        self.watchedIDs = watchedIDs
        self.favoritesIDs = favoritesIDs
        self.watchedEntries = watchedEntries
    }
}

extension UserProfile {
    static func empty(uid: String, email: String) -> UserProfile {
        UserProfile(id: uid,
                    email: email,
                    displayName: nil,
                    photoURL: nil,
                    createdAt: Date(),
                    watchlistIDs: [],
                    watchedIDs: [],
                    favoritesIDs: [],
                    watchedEntries: [])
    }
}

final class UserProfileRepository {
    private let db = Firestore.firestore()
    private var users: CollectionReference { db.collection("users") }

    func createOrMerge(_ profile: UserProfile) async throws {
        guard let uid = profile.id else {
            throw NSError(domain: "UserProfile", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing uid"])
        }

        let createdAtTimestamp = Timestamp(date: profile.createdAt)

        let data: [String: Any] = [
            "email": profile.email,
            "createdAt": createdAtTimestamp,
            "watchlistIDs": profile.watchlistIDs,
            "watchedIDs": profile.watchedIDs,
            "favoritesIDs": profile.favoritesIDs,
            "watchedEntries": profile.watchedEntries.map { ["id": $0.id, "type": $0.type] }
        ].merging(optional: [
            "displayName": profile.displayName,
            "photoURL": profile.photoURL
        ])

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

        guard snapshot.exists, let dict = snapshot.data() else {
            throw NSError(domain: "UserProfile", code: 1, userInfo: [NSLocalizedDescriptionKey: "User profile not found"])
        }

        let email = dict["email"] as? String ?? ""
        let displayName = dict["displayName"] as? String
        let photoURL = dict["photoURL"] as? String

        let createdAtDate: Date = {
            if let ts = dict["createdAt"] as? Timestamp {
                return ts.dateValue()
            } else if let date = dict["createdAt"] as? Date {
                return date
            } else {
                return Date(timeIntervalSince1970: 0)
            }
        }()

        func ints(from any: Any?) -> [Int] {
            if let arr = any as? [Int] { return arr }
            if let arr = any as? [String] {
                return arr.compactMap { Int($0.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) }
            }
            return []
        }

        let watchlistIDs = ints(from: dict["watchlistIDs"])
        let watchedIDs = ints(from: dict["watchedIDs"])
        let favoritesIDs = ints(from: dict["favoritesIDs"])

        let watchedEntries: [WatchedEntry] = {
            if let arr = dict["watchedEntries"] as? [[String: Any]] {
                return arr.compactMap { m in
                    if let id = m["id"] as? Int, let type = m["type"] as? String {
                        return WatchedEntry(id: id, type: type)
                    } else if let idNum = m["id"] as? NSNumber, let type = m["type"] as? String {
                        return WatchedEntry(id: idNum.intValue, type: type)
                    }
                    return nil
                }
            } else if !watchedIDs.isEmpty {
                // backward compatibility: assume movie
                return watchedIDs.map { WatchedEntry(id: $0, type: "movie") }
            } else {
                return []
            }
        }()

        return UserProfile(
            id: snapshot.documentID,
            email: email,
            displayName: displayName,
            photoURL: photoURL,
            createdAt: createdAtDate,
            watchlistIDs: watchlistIDs,
            watchedIDs: watchedIDs,
            favoritesIDs: favoritesIDs,
            watchedEntries: watchedEntries
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

    func addToFavorites(uid: String, id: Int) async throws {
        try await updateArrayField(uid: uid, field: "favoritesIDs", add: [id])
    }

    func removeFromFavorites(uid: String, id: Int) async throws {
        try await updateArrayField(uid: uid, field: "favoritesIDs", remove: [id])
    }

    func addToWatchlist(uid: String, id: Int) async throws {
        try await updateArrayField(uid: uid, field: "watchlistIDs", add: [id])
    }

    func removeFromWatchlist(uid: String, id: Int) async throws {
        try await updateArrayField(uid: uid, field: "watchlistIDs", remove: [id])
    }

    // NEW: typed watched entries
    func addToWatched(uid: String, entry: WatchedEntry) async throws {
        try await updateArrayField(uid: uid, field: "watchedEntries", add: [["id": entry.id, "type": entry.type]])
    }

    func removeFromWatched(uid: String, entry: WatchedEntry) async throws {
        try await updateArrayField(uid: uid, field: "watchedEntries", remove: [["id": entry.id, "type": entry.type]])
    }

    // Backward-compat (not used after migration, but keep)
    func addToWatched(uid: String, id: Int) async throws {
        try await updateArrayField(uid: uid, field: "watchedIDs", add: [id])
    }

    func removeFromWatched(uid: String, id: Int) async throws {
        try await updateArrayField(uid: uid, field: "watchedIDs", remove: [id])
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

