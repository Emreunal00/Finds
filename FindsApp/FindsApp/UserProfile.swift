import Foundation
import FirebaseFirestore

struct UserProfile: Codable, Identifiable, Equatable {
    var id: String? // Firebase Auth uid
    var email: String
    var displayName: String?
    var photoURL: String?
    var createdAt: Date
    var watchlistIDs: [Int]
    var watchedIDs: [Int]
    var favoritesIDs: [Int]

    init(id: String? = nil,
         email: String,
         displayName: String? = nil,
         photoURL: String? = nil,
         createdAt: Date = Date(),
         watchlistIDs: [Int] = [],
         watchedIDs: [Int] = [],
         favoritesIDs: [Int] = []) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.photoURL = photoURL
        self.createdAt = createdAt
        self.watchlistIDs = watchlistIDs
        self.watchedIDs = watchedIDs
        self.favoritesIDs = favoritesIDs
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
                    favoritesIDs: [])
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
            "favoritesIDs": profile.favoritesIDs
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

        // Tolerance: if old data used String tokens, try converting them to Int
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

        return UserProfile(
            id: snapshot.documentID,
            email: email,
            displayName: displayName,
            photoURL: photoURL,
            createdAt: createdAtDate,
            watchlistIDs: watchlistIDs,
            watchedIDs: watchedIDs,
            favoritesIDs: favoritesIDs
        )
    }

    // MARK: - Array field helpers (Int-based)

    private func updateArrayField(uid: String, field: String, add values: [Int]? = nil, remove valuesToRemove: [Int]? = nil) async throws {
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
