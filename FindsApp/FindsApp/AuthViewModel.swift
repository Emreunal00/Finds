import Foundation
import Combine
import FirebaseAuth

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
                debugPrint("[Auth] Initial profile fetched. favorites=\(profile.favoritesIDs.count) watchlist=\(profile.watchlistIDs.count) watched=\(profile.watchedEntries.count)")

                profileObserver = service.observeProfile(uid: uid) { [weak self] result in
                    Task { @MainActor in
                        switch result {
                        case .success(let updated):
                            self?.user = updated
                            self?.listsVersion &+= 1
                            debugPrint("[Auth] Profile updated via listener. counts fav=\(updated.favoritesIDs.count) watch=\(updated.watchlistIDs.count) watched=\(updated.watchedEntries.count) listsVersion=\(self?.listsVersion ?? -1)")
                        case .failure(let err):
                            debugPrint("[Auth] Profile listener error:", err.localizedDescription)
                        }
                    }
                }
                debugPrint("[Auth] Profile listener started")
            } catch {
                let mapped = Self.mapAuthError(error)
                self.errorMessage = mapped.userMessage
                debugPrint("[Auth] Fetch profile failed:", mapped.debugDescription)
            }
        } else {
            self.user = nil
            debugPrint("[Auth] Auth state changed -> signed out")
        }
    }

    func signUp(email: String, password: String, displayName: String?) async { /* unchanged */ }

    func signIn(email: String, password: String) async { /* unchanged */ }

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

    // MARK: - Favorites / Watchlist

    func toggleFavorite(movieID: Int) async { /* unchanged from your latest with small delay if you prefer */ }

    func toggleWatchlist(movieID: Int) async { /* unchanged from your latest with small delay if you prefer */ }

    // MARK: - Watched (typed)

    func toggleWatched(movieID: Int, type: String) async {
        guard let uid = service.currentUID else {
            self.errorMessage = "No active session."
            return
        }
        debugPrint("[ToggleWatchedTyped] start id=\(movieID) type=\(type)")
        do {
            let repo = UserProfileRepository()
            let current = try await service.fetchProfile(uid: uid)

            let entry = WatchedEntry(id: movieID, type: type)
            var hasEntry = current.watchedEntries.contains(where: { $0.id == entry.id && $0.type == entry.type })

            // Backward compat: if in legacy watchedIDs and type == movie, consider as present
            if !hasEntry && type == "movie" && current.watchedIDs.contains(movieID) {
                hasEntry = true
            }

            if hasEntry {
                try await repo.removeFromWatched(uid: uid, entry: entry)
                debugPrint("[ToggleWatchedTyped] removed entry=\(entry)")
            } else {
                try await repo.addToWatched(uid: uid, entry: entry)
                debugPrint("[ToggleWatchedTyped] added entry=\(entry)")
            }

            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
            self.user = try await service.fetchProfile(uid: uid)
            self.listsVersion &+= 1
            debugPrint("[ToggleWatchedTyped] done. watchedEntries=\(self.user?.watchedEntries.count ?? 0) listsVersion=\(self.listsVersion)")
        } catch {
            self.errorMessage = error.localizedDescription
            debugPrint("[ToggleWatchedTyped] error:", error.localizedDescription)
        }
    }

    // Backward compat: if caller doesn't know type, assume "movie"
    func toggleWatched(movieID: Int) async {
        await toggleWatched(movieID: movieID, type: "movie")
    }
}

// MARK: - Error Mapping (unchanged)
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

