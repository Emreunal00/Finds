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
}

final class AuthService: AuthServicing {
    private let auth: Auth
    private let userRepo: UserProfileRepository
    private var authHandle: AuthStateDidChangeListenerHandle?

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
        // users doc yoksa oluştur
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

    deinit {
        if let handle = authHandle {
            auth.removeStateDidChangeListener(handle)
        }
    }
}

