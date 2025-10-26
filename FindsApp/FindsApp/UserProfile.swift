import Foundation
import FirebaseFirestore
import FirebaseFirestoreSwift

struct UserProfile: Codable, Identifiable, Equatable {
    @DocumentID var id: String? // Firebase Auth uid
    var email: String
    var displayName: String?
    var photoURL: String?
    var createdAt: Date
    var watchlistIDs: [String]
    var watchedIDs: [String]

    init(id: String? = nil,
         email: String,
         displayName: String? = nil,
         photoURL: String? = nil,
         createdAt: Date = Date(),
         watchlistIDs: [String] = [],
         watchedIDs: [String] = []) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.photoURL = photoURL
        self.createdAt = createdAt
        self.watchlistIDs = watchlistIDs
        self.watchedIDs = watchedIDs
    }
}

extension UserProfile {
    static func empty(uid: String, email: String) -> UserProfile {
        UserProfile(id: uid, email: email, displayName: nil, photoURL: nil, createdAt: Date(), watchlistIDs: [], watchedIDs: [])
    }
}

final class UserProfileRepository {
    private let db = Firestore.firestore()
    private var users: CollectionReference { db.collection("users") }

    func createOrMerge(_ profile: UserProfile) async throws {
        guard let uid = profile.id else { throw NSError(domain: "UserProfile", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing uid"]) }
        try users.document(uid).setData(from: profile, merge: true)
    }

    func fetch(uid: String) async throws -> UserProfile {
        let snapshot = try await users.document(uid).getDocument()
        if let profile = try snapshot.data(as: UserProfile.self) {
            return profile
        } else {
            throw NSError(domain: "UserProfile", code: 1, userInfo: [NSLocalizedDescriptionKey: "User profile not found"])
        }
    }
}

