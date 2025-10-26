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

    init(service: AuthServicing = AuthService()) {
        self.service = service
        self.authObserver = service.observeAuthState { [weak self] uid in
            Task { await self?.handleAuthChange(uid: uid) }
        }
    }

    private func handleAuthChange(uid: String?) async {
        if let uid {
            do {
                let profile = try await service.fetchProfile(uid: uid)
                self.user = profile
                self.errorMessage = nil
                debugPrint("[Auth] Auth state changed -> signed in uid=\(uid)")
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

    func signUp(email: String, password: String, displayName: String?) async {
        isLoading = true
        errorMessage = nil

        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            self.errorMessage = "Please enter a name."
            self.isLoading = false
            return
        }

        do {
            let profile = try await service.signUp(email: email, password: password, displayName: trimmed)
            self.user = profile
            debugPrint("[Auth] SignUp success for email:", email)
        } catch {
            let mapped = Self.mapAuthError(error)
            self.errorMessage = mapped.userMessage
            debugPrint("[Auth] SignUp failed:", mapped.debugDescription)
        }
        isLoading = false
    }

    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let profile = try await service.signIn(email: email, password: password)
            self.user = profile
            debugPrint("[Auth] SignIn success for email:", email)
        } catch {
            let mapped = Self.mapAuthError(error)
            self.errorMessage = mapped.userMessage
            debugPrint("[Auth] SignIn failed:", mapped.debugDescription)
        }
        isLoading = false
    }

    func signOut() {
        do {
            try service.signOut()
            self.user = nil
            self.errorMessage = nil
            debugPrint("[Auth] SignOut success")
        } catch {
            let mapped = Self.mapAuthError(error)
            self.errorMessage = mapped.userMessage
            debugPrint("[Auth] SignOut failed:", mapped.debugDescription)
        }
    }

    // MARK: - Favorites / Watchlist / Watched (Int ID based)

    func toggleFavorite(movieID: Int) async {
        guard let uid = service.currentUID else {
            self.errorMessage = "No active session."
            return
        }
        do {
            let repo = UserProfileRepository()
            let current = try await service.fetchProfile(uid: uid)
            if current.favoritesIDs.contains(movieID) {
                try await repo.removeFromFavorites(uid: uid, id: movieID)
            } else {
                try await repo.addToFavorites(uid: uid, id: movieID)
            }
            self.user = try await service.fetchProfile(uid: uid)
            self.listsVersion &+= 1
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func toggleWatchlist(movieID: Int) async {
        guard let uid = service.currentUID else {
            self.errorMessage = "No active session."
            return
        }
        do {
            let repo = UserProfileRepository()
            let current = try await service.fetchProfile(uid: uid)
            if current.watchlistIDs.contains(movieID) {
                try await repo.removeFromWatchlist(uid: uid, id: movieID)
            } else {
                try await repo.addToWatchlist(uid: uid, id: movieID)
            }
            self.user = try await service.fetchProfile(uid: uid)
            self.listsVersion &+= 1
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func toggleWatched(movieID: Int) async {
        guard let uid = service.currentUID else {
            self.errorMessage = "No active session."
            return
        }
        do {
            let repo = UserProfileRepository()
            let current = try await service.fetchProfile(uid: uid)
            if current.watchedIDs.contains(movieID) {
                try await repo.removeFromWatched(uid: uid, id: movieID)
            } else {
                try await repo.addToWatched(uid: uid, id: movieID)
            }
            self.user = try await service.fetchProfile(uid: uid)
            self.listsVersion &+= 1
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Error Mapping

private extension AuthViewModel {
    struct MappedError {
        let userMessage: String
        let debugDescription: String
    }

    static func mapAuthError(_ error: Error) -> MappedError {
        let ns = error as NSError
        var userMessage = "An error occurred. Please try again."
        var debugDescription = "\(ns.domain) (\(ns.code)): \(ns.localizedDescription) userInfo=\(ns.userInfo)"

        if ns.domain == AuthErrorDomain, let code = AuthErrorCode(rawValue: ns.code) {
            switch code {
            case .invalidEmail:
                userMessage = "Invalid email address."
            case .emailAlreadyInUse:
                userMessage = "This email is already in use."
            case .weakPassword:
                userMessage = "Password must be at least 6 characters."
            case .wrongPassword:
                userMessage = "Incorrect email or password."
            case .userNotFound:
                userMessage = "No user found with this email."
            case .userDisabled:
                userMessage = "This account has been disabled."
            case .operationNotAllowed:
                userMessage = "This sign-in method is disabled. Enable Email/Password provider in Firebase Console."
            case .networkError:
                userMessage = "Network error. Check your internet connection."
            case .tooManyRequests:
                userMessage = "Too many attempts. Please try again later."
            case .internalError:
                userMessage = "A server error occurred. Please try again."
            default:
                userMessage = ns.localizedDescription
            }
        } else {
            userMessage = ns.localizedDescription
        }

        return MappedError(userMessage: userMessage, debugDescription: debugDescription)
    }
}
