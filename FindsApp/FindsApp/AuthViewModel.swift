import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var user: UserProfile?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var listsVersion = 0

    private let service: AuthServicing
    private var authObserver: Any?
    private var profileObserver: Any?

    init(service: AuthServicing = AuthService()) {
        self.service = service
        self.authObserver = service.observeAuthState { [weak self] uid in
            Task { await self?.handleAuthChange(uid: uid) }
        }
    }

    private func handleAuthChange(uid: String?) async {
        if let token = profileObserver {
            service.removeProfileObserver(token)
            profileObserver = nil
            debugPrint("[Auth] Removed previous profile observer")
        }

        if let uid {
            do {
                let profile = try await service.fetchProfile(uid: uid)
                self.user = profile
                self.errorMessage = nil
                debugPrint("[Auth] Auth state changed -> signed in uid=\(uid)")
                debugPrint("[Auth] Initial profile fetched. favEntries=\(profile.favoritesEntries.count) watchEntries=\(profile.watchlistEntries.count) watched=\(profile.watchedEntries.count)")

                profileObserver = service.observeProfile(uid: uid) { [weak self] result in
                    Task { @MainActor in
                        switch result {
                        case .success(let updated):
                            self?.user = updated
                            self?.listsVersion &+= 1
                            debugPrint("[Auth] Profile updated via listener. favEntries=\(updated.favoritesEntries.count) watchEntries=\(updated.watchlistEntries.count) watched=\(updated.watchedEntries.count) listsVersion=\(self?.listsVersion ?? -1)")
                        case .failure(let err):
                            debugPrint("[Auth] Profile listener error:", err.localizedDescription)
                        }
                    }
                }
                debugPrint("[Auth] Profile listener started")
            } catch {
                debugPrint("[Auth] Fetch profile failed (will rely on listener):", error.localizedDescription)
            }
        } else {
            self.user = nil
            debugPrint("[Auth] Auth state changed -> signed out")
        }
    }

    // MARK: - Auth

    func signUp(email: String, password: String, displayName: String?) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let profile = try await service.signUp(email: email, password: password, displayName: displayName)
            self.user = profile
            self.errorMessage = nil
            debugPrint("[Auth] SignUp success uid=\(profile.id ?? "-") email=\(profile.email)")
        } catch {
            let mapped = Self.mapAuthError(error)
            self.errorMessage = mapped.userMessage
            debugPrint("[Auth] SignUp failed:", mapped.debugDescription)
        }
    }

    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let profile = try await service.signIn(email: email, password: password)
            self.user = profile
            self.errorMessage = nil
            debugPrint("[Auth] SignIn success uid=\(profile.id ?? "-") email=\(profile.email)")
        } catch {
            let mapped = Self.mapAuthError(error)
            self.errorMessage = mapped.userMessage
            debugPrint("[Auth] SignIn failed:", mapped.debugDescription)
        }
    }

    func signOut() {
        do {
            try service.signOut()
            self.user = nil
            self.errorMessage = nil
            if let token = profileObserver {
                service.removeProfileObserver(token)
                profileObserver = nil
                debugPrint("[Auth] Removed profile observer on sign out")
            }
            debugPrint("[Auth] SignOut success")
        } catch {
            let mapped = Self.mapAuthError(error)
            self.errorMessage = mapped.userMessage
            debugPrint("[Auth] SignOut failed:", mapped.debugDescription)
        }
    }

    // MARK: - Profile updates

    func updateDisplayName(_ newName: String) async {
        guard let uid = service.currentUID else { self.errorMessage = "No active session."; return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { self.errorMessage = "Display name cannot be empty."; return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            // Update Firebase Auth displayName
            if let user = Auth.auth().currentUser {
                let change = user.createProfileChangeRequest()
                change.displayName = trimmed
                try await change.commitChanges()
            }

            // Merge into Firestore profile
            var current = try await service.fetchProfile(uid: uid)
            current.displayName = trimmed
            let repo = UserProfileRepository()
            try await repo.createOrMerge(current)

            // Refresh local state
            self.user = try await service.fetchProfile(uid: uid)
            debugPrint("[Auth] updateDisplayName success -> \(trimmed)")
        } catch {
            self.errorMessage = error.localizedDescription
            debugPrint("[Auth] updateDisplayName error:", error.localizedDescription)
        }
    }

    func updatePhotoURL(_ url: String) async {
        guard let uid = service.currentUID else { self.errorMessage = "No active session."; return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            // Update Firebase Auth photoURL (optional)
            if let user = Auth.auth().currentUser, let photoURL = URL(string: url) {
                let change = user.createProfileChangeRequest()
                change.photoURL = photoURL
                try await change.commitChanges()
            }

            // Merge into Firestore
            var current = try await service.fetchProfile(uid: uid)
            current.photoURL = url
            let repo = UserProfileRepository()
            try await repo.createOrMerge(current)

            // Refresh local state
            self.user = try await service.fetchProfile(uid: uid)
            debugPrint("[Auth] updatePhotoURL success")
        } catch {
            self.errorMessage = error.localizedDescription
            debugPrint("[Auth] updatePhotoURL error:", error.localizedDescription)
        }
    }

    // MARK: - List toggles (typed entries)

    func toggleFavorite(movieID: Int, mediaType: String) async {
        guard let uid = service.currentUID, var profile = self.user else {
            self.errorMessage = "No active session."
            return
        }
        let type = mediaType.lowercased()
        let entry = WatchedEntry(id: movieID, type: type)
        let repo = UserProfileRepository()

        if let idx = profile.favoritesEntries.firstIndex(where: { $0.id == movieID && $0.type.lowercased() == type }) {
            do {
                try await repo.removeFromFavorites(uid: uid, entry: entry)
                profile.favoritesEntries.remove(at: idx)
                self.user = profile
                self.listsVersion &+= 1
            } catch {
                self.errorMessage = error.localizedDescription
            }
        } else {
            do {
                try await repo.addToFavorites(uid: uid, entry: entry)
                profile.favoritesEntries.append(entry)
                self.user = profile
                self.listsVersion &+= 1
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func toggleWatchlist(movieID: Int, mediaType: String) async {
        guard let uid = service.currentUID, var profile = self.user else {
            self.errorMessage = "No active session."
            return
        }
        let type = mediaType.lowercased()
        let entry = WatchedEntry(id: movieID, type: type)
        let repo = UserProfileRepository()

        if let idx = profile.watchlistEntries.firstIndex(where: { $0.id == movieID && $0.type.lowercased() == type }) {
            do {
                try await repo.removeFromWatchlist(uid: uid, entry: entry)
                profile.watchlistEntries.remove(at: idx)
                self.user = profile
                self.listsVersion &+= 1
            } catch {
                self.errorMessage = error.localizedDescription
            }
        } else {
            do {
                try await repo.addToWatchlist(uid: uid, entry: entry)
                profile.watchlistEntries.append(entry)
                self.user = profile
                self.listsVersion &+= 1
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func toggleWatched(movieID: Int, type: String) async {
        guard let uid = service.currentUID, var profile = self.user else {
            self.errorMessage = "No active session."
            return
        }
        let normType = type.lowercased()
        let entry = WatchedEntry(id: movieID, type: normType)
        let repo = UserProfileRepository()

        if let idx = profile.watchedEntries.firstIndex(where: { $0.id == movieID && $0.type.lowercased() == normType }) {
            do {
                try await repo.removeFromWatched(uid: uid, entry: entry)
                profile.watchedEntries.remove(at: idx)
                self.user = profile
                self.listsVersion &+= 1
            } catch {
                self.errorMessage = error.localizedDescription
            }
        } else {
            do {
                try await repo.addToWatched(uid: uid, entry: entry)
                profile.watchedEntries.append(entry)
                self.user = profile
                self.listsVersion &+= 1
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Error Mapping
private extension AuthViewModel {
    struct MappedError { let userMessage: String; let debugDescription: String }
    static func mapAuthError(_ error: Error) -> MappedError {
        let ns = error as NSError
        var userMessage = "An error occurred. Please try again."
        var debugDescription = "\(ns.domain) (\(ns.code)): \(ns.localizedDescription) userInfo=\(ns.userInfo)"
        if ns.domain == AuthErrorDomain, let code = AuthErrorCode(rawValue: ns.code) {
            switch code {
            case .invalidEmail: userMessage = "Invalid email address."
            case .emailAlreadyInUse: userMessage = "This email is already in use."
            case .weakPassword: userMessage = "Password must be at least 6 characters."
            case .wrongPassword: userMessage = "Incorrect email or password."
            case .userNotFound: userMessage = "No user found with this email."
            case .userDisabled: userMessage = "This account has been disabled."
            case .operationNotAllowed: userMessage = "This sign-in method is disabled. Enable Email/Password provider in Firebase Console."
            case .networkError: userMessage = "Network error. Check your internet connection."
            case .tooManyRequests: userMessage = "Too many attempts. Please try again later."
            case .internalError: userMessage = "A server error occurred. Please try again."
            default: userMessage = ns.localizedDescription
            }
        } else {
            userMessage = ns.localizedDescription
        }
        return MappedError(userMessage: userMessage, debugDescription: debugDescription)
    }
}
