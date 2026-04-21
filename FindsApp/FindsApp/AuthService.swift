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

    // Realtime profile listener
    func observeProfile(uid: String, onChange: @escaping (Result<UserProfile, Error>) -> Void) -> Any
    func removeProfileObserver(_ token: Any)
}

final class AuthService: AuthServicing {
    private let auth: Auth
    private let userRepo: UserProfileRepository
    private var authHandle: AuthStateDidChangeListenerHandle?
    private var profileListenerHandle: ListenerRegistration?

    init(auth: Auth = Auth.auth(), userRepo: UserProfileRepository = UserProfileRepository()) {
        self.auth = auth
        self.userRepo = userRepo
    }

    var currentUID: String? { auth.currentUser?.uid }

    // Sign Up: only create user + write profile; do NOT block on fetching the profile
    func signUp(email: String, password: String, displayName: String?) async throws -> UserProfile {
        let result = try await auth.createUser(withEmail: email, password: password)

        if let displayName {
            let change = result.user.createProfileChangeRequest()
            change.displayName = displayName
            try await change.commitChanges()
        }

        let uid = result.user.uid
        // Write minimal profile; do not wait for read-back
        let initialProfile = Profile(displayName: displayName)
        let minimalProfile = UserProfile(
            id: uid,
            email: email,
            watchlistIDs: [],
            watchedIDs: [],
            favoritesIDs: [],
            profiles: [initialProfile],
            selectedProfileID: initialProfile.id
        )
        try await userRepo.createOrMerge(minimalProfile)

        // Return minimal profile; AuthViewModel will receive live updates via listener
        return minimalProfile
    }

    func signIn(email: String, password: String) async throws -> UserProfile {
        let result = try await auth.signIn(withEmail: email, password: password)
        let uid = result.user.uid
        do {
            return try await retryFetchProfile(uid: uid, maxAttempts: 3, initialDelay: 0.2)
        } catch {
            // If profile not found, create and retry fetch
            let profile = UserProfile.empty(uid: uid, email: email)
            try await userRepo.createOrMerge(profile)
            return try await retryFetchProfile(uid: uid, maxAttempts: 3, initialDelay: 0.2)
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

    func observeProfile(uid: String, onChange: @escaping (Result<UserProfile, Error>) -> Void) -> Any {
        profileListenerHandle?.remove()

        let handle = Firestore.firestore()
            .collection("users")
            .document(uid)
            .addSnapshotListener { snapshot, error in
                if let error {
                    onChange(.failure(error)); return
                }
                guard let snapshot, snapshot.exists else {
                    onChange(.failure(NSError(domain: "UserProfile", code: 404, userInfo: [NSLocalizedDescriptionKey: "Profile not found"]))); return
                }
                do {
                    let profile = try self.userRepo.decode(snapshot: snapshot)
                    onChange(.success(profile))
                } catch {
                    onChange(.failure(error))
                }
            }

        profileListenerHandle = handle
        return handle as Any
    }

    func removeProfileObserver(_ token: Any) {
        if let handle = token as? ListenerRegistration { handle.remove() }
        if let handle = profileListenerHandle { handle.remove(); profileListenerHandle = nil }
    }

    deinit {
        if let handle = authHandle { auth.removeStateDidChangeListener(handle) }
        profileListenerHandle?.remove()
    }

    // MARK: - Retry helper (still used by Sign In only)

    private func retryFetchProfile(uid: String, maxAttempts: Int = 3, initialDelay: TimeInterval = 0.2) async throws -> UserProfile {
        var attempt = 0
        var delay = initialDelay
        var lastError: Error?

        while attempt < maxAttempts {
            do {
                return try await userRepo.fetch(uid: uid)
            } catch {
                lastError = error
                let ns = error as NSError
                let offlineLike =
                    ns.domain == NSURLErrorDomain ||
                    ns.domain.localizedCaseInsensitiveContains("FIR") ||
                    ns.domain.localizedCaseInsensitiveContains("Firestore") ||
                    ns.localizedDescription.localizedCaseInsensitiveContains("offline") ||
                    ns.localizedDescription.localizedCaseInsensitiveContains("unavailable")

                attempt += 1
                if attempt >= maxAttempts || !offlineLike {
                    break
                }
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                delay *= 2
            }
        }
        throw lastError ?? NSError(domain: "UserProfile", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch profile after retries"])
    }
}
