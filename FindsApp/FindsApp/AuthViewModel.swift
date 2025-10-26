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
                // Initial profile
                let profile = try await service.fetchProfile(uid: uid)
                self.user = profile
                self.errorMessage = nil
                debugPrint("[Auth] Auth state changed -> signed in uid=\(uid)")
                debugPrint("[Auth] Initial profile fetched. favEntries=\(profile.favoritesEntries.count) watchEntries=\(profile.watchlistEntries.count) watched=\(profile.watchedEntries.count)")

                // Realtime listener
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
                // Do not show error to user here; listener will likely deliver shortly.
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
        defer { isLoading = false } // Critically stop blocking UI regardless of fetch timing
        do {
            // This creates the auth user and writes the profile. It also tries to fetch,
            // but even if that fetch struggles, our auth state listener will kick in.
            let profile = try await service.signUp(email: email, password: password, displayName: displayName)
            // Optimistic: if we have it, set immediately. If not, handleAuthChange will set soon.
            self.user = profile
            self.errorMessage = nil
            debugPrint("[Auth] SignUp success uid=\(profile.id ?? "-") email=\(profile.email)")
        } catch {
            // If createUser succeeded but fetch failed transiently, handleAuthChange will still run.
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

    // MARK: - Favorites / Watchlist (typed)

    func toggleFavorite(movieID: Int, mediaType: String? = "movie") async {
        guard let uid = service.currentUID else { self.errorMessage = "No active session."; return }
        let type = (mediaType ?? "movie").lowercased()
        do {
            let repo = UserProfileRepository()
            let current = try await service.fetchProfile(uid: uid)
            let entry = WatchedEntry(id: movieID, type: type)
            let hasEntry = current.favoritesEntries.contains { $0.id == entry.id && $0.type.lowercased() == entry.type }
            if hasEntry {
                try await repo.removeFromFavorites(uid: uid, entry: entry)
                debugPrint("[ToggleFavoriteTyped] removed entry=\(entry)")
            } else {
                try await repo.addToFavorites(uid: uid, entry: entry)
                debugPrint("[ToggleFavoriteTyped] added entry=\(entry)")
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
            self.user = try await service.fetchProfile(uid: uid)
            self.listsVersion &+= 1
        } catch {
            self.errorMessage = error.localizedDescription
            debugPrint("[ToggleFavoriteTyped] error:", error.localizedDescription)
        }
    }

    func toggleWatchlist(movieID: Int, mediaType: String? = "movie") async {
        guard let uid = service.currentUID else { self.errorMessage = "No active session."; return }
        let type = (mediaType ?? "movie").lowercased()
        do {
            let repo = UserProfileRepository()
            let current = try await service.fetchProfile(uid: uid)
            let entry = WatchedEntry(id: movieID, type: type)
            let hasEntry = current.watchlistEntries.contains { $0.id == entry.id && $0.type.lowercased() == entry.type }
            if hasEntry {
                try await repo.removeFromWatchlist(uid: uid, entry: entry)
                debugPrint("[ToggleWatchlistTyped] removed entry=\(entry)")
            } else {
                try await repo.addToWatchlist(uid: uid, entry: entry)
                debugPrint("[ToggleWatchlistTyped] added entry=\(entry)")
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
            self.user = try await service.fetchProfile(uid: uid)
            self.listsVersion &+= 1
        } catch {
            self.errorMessage = error.localizedDescription
            debugPrint("[ToggleWatchlistTyped] error:", error.localizedDescription)
        }
    }

    // MARK: - Watched (typed)

    func toggleWatched(movieID: Int, type: String) async {
        guard let uid = service.currentUID else { self.errorMessage = "No active session."; return }
        let normalizedType = type.lowercased()
        debugPrint("[ToggleWatchedTyped] start id=\(movieID) type=\(normalizedType)")
        do {
            let repo = UserProfileRepository()
            let current = try await service.fetchProfile(uid: uid)

            let entry = WatchedEntry(id: movieID, type: normalizedType)
            let hasEntry = current.watchedEntries.contains { $0.id == entry.id && $0.type.lowercased() == entry.type }

            if hasEntry {
                try await repo.removeFromWatched(uid: uid, entry: entry)
                debugPrint("[ToggleWatchedTyped] removed entry=\(entry)")
            } else {
                try await repo.addToWatched(uid: uid, entry: entry)
                debugPrint("[ToggleWatchedTyped] added entry=\(entry)")
            }

            try? await Task.sleep(nanoseconds: 200_000_000)
            self.user = try await service.fetchProfile(uid: uid)
            self.listsVersion &+= 1
            debugPrint("[ToggleWatchedTyped] done. watchedEntries=\(self.user?.watchedEntries.count ?? 0) listsVersion=\(self.listsVersion)")
        } catch {
            self.errorMessage = error.localizedDescription
            debugPrint("[ToggleWatchedTyped] error:", error.localizedDescription)
        }
    }

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
