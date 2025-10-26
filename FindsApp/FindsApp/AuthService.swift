import Foundation
import FirebaseAuth
import FirebaseFirestore

protocol AuthServicing {
    var currentUID: String? { get }
    func signUp(email: String, password: String, displayName: String?) async throws -> UserProfile
    func signIn(email: String, password: String) async throws -> UserProfile
    func signOut() throws
    func observeAuthState(_ onChange: @escaping (String?) -> Void) -> Any
    func fetchProfile(uid: String) async throws -> UserProfile

    // NEW: Realtime profile listener
    func observeProfile(uid: String, onChange: @escaping (Result<UserProfile, Error>) -> Void) -> Any
    func removeProfileObserver(_ token: Any)
}

final class AuthService: AuthServicing {
    private let auth: Auth
    private let userRepo: UserProfileRepository
    private var authHandle: AuthStateDidChangeListenerHandle?

    // Keep profile listener handle to remove later if needed
    private var profileListenerHandle: ListenerRegistration?

    init(auth: Auth = Auth.auth(), userRepo: UserProfileRepository = UserProfileRepository()) {
        self.auth = auth
        self.userRepo = userRepo
    }

    var currentUID: String? { auth.currentUser?.uid }

    func signUp(email: String, password: String, displayName: String?) async throws -> UserProfile {
        let result = try await auth.createUser(withEmail: email, password: password)
        if let displayName {
            let change = result.user.createProfileChangeRequest()
            change.displayName = displayName
            try await change.commitChanges()
        }
        let uid = result.user.uid
        var profile = UserProfile.empty(uid: uid, email: email)
        profile.displayName = displayName ?? result.user.displayName
        try await userRepo.createOrMerge(profile)
        return try await userRepo.fetch(uid: uid)
    }

    func signIn(email: String, password: String) async throws -> UserProfile {
        let result = try await auth.signIn(withEmail: email, password: password)
        let uid = result.user.uid
        do {
            return try await userRepo.fetch(uid: uid)
        } catch {
            let profile = UserProfile.empty(uid: uid, email: email)
            try await userRepo.createOrMerge(profile)
            return try await userRepo.fetch(uid: uid)
        }
    }

    func signOut() throws {
        try auth.signOut()
    }

    func observeAuthState(_ onChange: @escaping (String?) -> Void) -> Any {
        let handle = auth.addStateDidChangeListener { _, user in
            onChange(user?.uid)
        }
        self.authHandle = handle
        return handle as Any
    }

    func fetchProfile(uid: String) async throws -> UserProfile {
        try await userRepo.fetch(uid: uid)
    }

    // MARK: - Realtime profile observing

    func observeProfile(uid: String, onChange: @escaping (Result<UserProfile, Error>) -> Void) -> Any {
        // Remove previous if any
        profileListenerHandle?.remove()

        let handle = Firestore.firestore()
            .collection("users")
            .document(uid)
            .addSnapshotListener { snapshot, error in
                if let error {
                    onChange(.failure(error))
                    return
                }
                guard let snapshot, snapshot.exists else {
                    onChange(.failure(NSError(domain: "UserProfile", code: 404, userInfo: [NSLocalizedDescriptionKey: "Profile not found"])))
                    return
                }
                let dict = snapshot.data() ?? [:]
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

                // Parse watchedEntries (typed) similar to repository
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
                    } else if let legacy = dict["watchedIDs"] {
                        let ids = ints(from: legacy)
                        return ids.map { WatchedEntry(id: $0, type: "movie") }
                    } else {
                        return []
                    }
                }()

                let profile = UserProfile(
                    id: snapshot.documentID,
                    email: email,
                    displayName: displayName,
                    photoURL: photoURL,
                    createdAt: createdAtDate,
                    watchlistIDs: ints(from: dict["watchlistIDs"]),
                    watchedIDs: ints(from: dict["watchedIDs"]),
                    favoritesIDs: ints(from: dict["favoritesIDs"]),
                    watchedEntries: watchedEntries
                )
                onChange(.success(profile))
            }

        profileListenerHandle = handle
        return handle as Any
    }

    func removeProfileObserver(_ token: Any) {
        if let handle = token as? ListenerRegistration {
            handle.remove()
        }
        if let handle = profileListenerHandle {
            handle.remove()
            profileListenerHandle = nil
        }
    }

    deinit {
        if let handle = authHandle {
            auth.removeStateDidChangeListener(handle)
        }
        profileListenerHandle?.remove()
    }
}
