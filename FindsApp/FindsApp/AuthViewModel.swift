import Foundation
import Combine

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var user: UserProfile?
    @Published var isLoading = false
    @Published var errorMessage: String?

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
            } catch {
                self.errorMessage = error.localizedDescription
            }
        } else {
            self.user = nil
        }
    }

    func signUp(email: String, password: String, displayName: String?) async {
        isLoading = true
        errorMessage = nil
        do {
            let profile = try await service.signUp(email: email, password: password, displayName: displayName)
            self.user = profile
        } catch {
            self.errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let profile = try await service.signIn(email: email, password: password)
            self.user = profile
        } catch {
            self.errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func signOut() {
        do {
            try service.signOut()
            self.user = nil
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}

