import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var user: UserProfile?

    /// Currently selected user profile (if available)
    var currentProfile: Profile? {
        guard let user = user, let selectedID = user.selectedProfileID else { return user?.profiles.first }
        return user.profiles.first(where: { $0.id == selectedID }) ?? user.profiles.first
    }

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
                let normalizedProfile = await ensureProfileExistsIfNeeded(profile)
                self.user = normalizedProfile
                self.errorMessage = nil
                debugPrint("[Auth] Auth state changed -> signed in uid=\(uid)")
                let initialProfile = self.currentProfile
                debugPrint("[Auth] Initial profile fetched. favEntries=\(initialProfile?.favoritesEntries.count ?? 0) watchEntries=\(initialProfile?.watchlistEntries.count ?? 0) watched=\(initialProfile?.watchedEntries.count ?? 0)")

                profileObserver = service.observeProfile(uid: uid) { [weak self] result in
                    Task { @MainActor in
                        switch result {
                        case .success(let updated):
                            let normalizedProfile = await self?.ensureProfileExistsIfNeeded(updated) ?? updated
                            self?.user = normalizedProfile
                            self?.listsVersion &+= 1
                            let active = self?.currentProfile
                            debugPrint("[Auth] Profile updated via listener. favEntries=\(active?.favoritesEntries.count ?? 0) watchEntries=\(active?.watchlistEntries.count ?? 0) watched=\(active?.watchedEntries.count ?? 0) listsVersion=\(self?.listsVersion ?? -1)")
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

    private func ensureProfileExistsIfNeeded(_ userProfile: UserProfile) async -> UserProfile {
        guard userProfile.profiles.isEmpty else { return userProfile }

        var updatedUser = userProfile
        let fallbackName = Auth.auth().currentUser?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let emailPrefix = userProfile.email.split(separator: "@").first.map(String.init)
        let profileName = fallbackName?.isEmpty == false ? fallbackName : (emailPrefix?.isEmpty == false ? emailPrefix : "Profile 1")
        let profile = Profile(displayName: profileName, photoURL: nil)

        updatedUser.profiles = [profile]
        updatedUser.selectedProfileID = profile.id

        let repo = UserProfileRepository()
        try? await repo.createOrMerge(updatedUser)
        return updatedUser
    }

    // MARK: - Profile Management

    /// Selects active profile by id and persists to user
    func selectProfile(_ profileID: String) {
        guard var user = user else { return }
        user.selectedProfileID = profileID
        self.user = user
        // Optionally persist to backend
        Task {
            let repo = UserProfileRepository()
            try? await repo.createOrMerge(user)
        }
    }

    /// Adds a new profile (with optional displayName and photoURL)
    func addProfile(displayName: String?, photoURL: String?) async {
        guard var user = user else { return }
        var profiles = user.profiles
        let profile = Profile(displayName: displayName, photoURL: photoURL)
        profiles.append(profile)
        user.profiles = profiles
        user.selectedProfileID = profile.id
        self.user = user
        let repo = UserProfileRepository()
        try? await repo.createOrMerge(user)
    }

    /// Deletes a profile by id (switches to another if needed)
    func deleteProfile(_ profileID: String) async throws {
        guard var user = user else { return }
        guard user.profiles.count > 1 else { return }

        let uid = user.id
        let wasSelected = user.selectedProfileID == profileID
        debugPrint("[Auth] deleteProfile start profileID=\(profileID) uid=\(uid ?? "-") profilesBefore=\(user.profiles.map(\.id)) selected=\(user.selectedProfileID ?? "-")")
        user.profiles.removeAll { $0.id == profileID }
        if wasSelected {
            user.selectedProfileID = user.profiles.first?.id
        }

        self.user = user
        let repo = UserProfileRepository()
        try await repo.createOrMerge(user)
        debugPrint("[Auth] deleteProfile persisted profileID=\(profileID) profilesAfter=\(user.profiles.map(\.id)) selected=\(user.selectedProfileID ?? "-")")

        if let uid {
            debugPrint("[Auth] deleteProfile cleanup start profileID=\(profileID)")
            await removeProfileScopedData(uid: uid, profileID: profileID)
            debugPrint("[Auth] deleteProfile cleanup end profileID=\(profileID)")
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

    private func removeProfileScopedData(uid: String, profileID: String) async {
        let db = Firestore.firestore()
        let profileDoc = db.collection("users").document(uid).collection("profiles").document(profileID)
        do {
            let listsSnapshot = try await profileDoc.collection("lists").getDocuments()
            debugPrint("[Auth] removeProfileScopedData listsCount=\(listsSnapshot.documents.count) profileID=\(profileID)")

            for listDoc in listsSnapshot.documents {
                let itemsSnapshot = try? await listDoc.reference.collection("items").getDocuments()
                debugPrint("[Auth] removeProfileScopedData deleting listID=\(listDoc.documentID) itemsCount=\(itemsSnapshot?.documents.count ?? 0)")
                for itemDoc in itemsSnapshot?.documents ?? [] {
                    try? await itemDoc.reference.delete()
                }
                try? await listDoc.reference.delete()
            }

            try? await profileDoc.delete()
        } catch {
            debugPrint("[Auth] removeProfileScopedData error:", error.localizedDescription)
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
            if let selectedID = current.selectedProfileID, let idx = current.profiles.firstIndex(where: { $0.id == selectedID }) {
                current.profiles[idx].displayName = trimmed
            } else if !current.profiles.isEmpty {
                current.profiles[0].displayName = trimmed
            }
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
            if let selectedID = current.selectedProfileID, let idx = current.profiles.firstIndex(where: { $0.id == selectedID }) {
                current.profiles[idx].photoURL = url
            } else if !current.profiles.isEmpty {
                current.profiles[0].photoURL = url
            }
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

    func toggleFavorite(movieID: Int, mediaType: String, externalContentID: String? = nil) async {
        guard let uid = service.currentUID, var user = self.user else {
            self.errorMessage = "No active session."
            return
        }
        guard let profile = currentProfile else {
            self.errorMessage = "No active profile."
            return
        }
        let type = mediaType.lowercased()
        let entry = WatchedEntry(id: movieID, type: type, externalID: externalContentID)
        let repo = UserProfileRepository()

        var updatedUser = user

        if let idx = profile.favoritesEntries.firstIndex(where: { $0.id == movieID && $0.type.lowercased() == type }) {
            do {
                // Update the profile's favoritesEntries
                updatedUser.profiles = updatedUser.profiles.map { p in
                    guard p.id == profile.id else { return p }
                    var copy = p
                    copy.favoritesEntries.remove(at: idx)
                    return copy
                }
                try await repo.createOrMerge(updatedUser)
                self.user = updatedUser
                self.listsVersion &+= 1
            } catch {
                self.errorMessage = error.localizedDescription
            }
        } else {
            do {
                updatedUser.profiles = updatedUser.profiles.map { p in
                    guard p.id == profile.id else { return p }
                    var copy = p
                    copy.favoritesEntries.append(entry)
                    return copy
                }
                try await repo.createOrMerge(updatedUser)
                self.user = updatedUser
                self.listsVersion &+= 1
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func toggleWatchlist(movieID: Int, mediaType: String, externalContentID: String? = nil) async {
        guard let uid = service.currentUID, var user = self.user else {
            self.errorMessage = "No active session."
            return
        }
        guard let profile = currentProfile else {
            self.errorMessage = "No active profile."
            return
        }
        let type = mediaType.lowercased()
        let entry = WatchedEntry(id: movieID, type: type, externalID: externalContentID)
        let repo = UserProfileRepository()

        var updatedUser = user

        if let idx = profile.watchlistEntries.firstIndex(where: { $0.id == movieID && $0.type.lowercased() == type }) {
            do {
                updatedUser.profiles = updatedUser.profiles.map { p in
                    guard p.id == profile.id else { return p }
                    var copy = p
                    copy.watchlistEntries.remove(at: idx)
                    if type == "book" {
                        copy.booksWantToReadEntries.removeAll { $0.id == movieID && $0.type.lowercased() == type }
                    }
                    return copy
                }
                try await repo.createOrMerge(updatedUser)
                self.user = updatedUser
                self.listsVersion &+= 1
            } catch {
                self.errorMessage = error.localizedDescription
            }
        } else {
            do {
                updatedUser.profiles = updatedUser.profiles.map { p in
                    guard p.id == profile.id else { return p }
                    var copy = p
                    copy.watchlistEntries.append(entry)
                    if type == "book" {
                        copy.booksWantToReadEntries.append(entry)
                    }
                    return copy
                }
                try await repo.createOrMerge(updatedUser)
                self.user = updatedUser
                self.listsVersion &+= 1
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func toggleWatched(movieID: Int, type: String, externalContentID: String? = nil) async {
        guard let uid = service.currentUID, var user = self.user else {
            self.errorMessage = "No active session."
            return
        }
        guard let profile = currentProfile else {
            self.errorMessage = "No active profile."
            return
        }
        let normType = type.lowercased()
        let entry = WatchedEntry(id: movieID, type: normType, externalID: externalContentID)
        let repo = UserProfileRepository()

        var updatedUser = user

        if let idx = profile.watchedEntries.firstIndex(where: { $0.id == movieID && $0.type.lowercased() == normType }) {
            do {
                updatedUser.profiles = updatedUser.profiles.map { p in
                    guard p.id == profile.id else { return p }
                    var copy = p
                    copy.watchedEntries.remove(at: idx)
                    if normType == "book" {
                        copy.booksReadEntries.removeAll { $0.id == movieID && $0.type.lowercased() == normType }
                    }
                    return copy
                }
                try await repo.createOrMerge(updatedUser)
                self.user = updatedUser
                self.listsVersion &+= 1
            } catch {
                self.errorMessage = error.localizedDescription
            }
        } else {
            do {
                updatedUser.profiles = updatedUser.profiles.map { p in
                    guard p.id == profile.id else { return p }
                    var copy = p
                    copy.watchedEntries.append(entry)
                    if normType == "book" {
                        copy.booksReadEntries.append(entry)
                    }
                    return copy
                }
                try await repo.createOrMerge(updatedUser)
                self.user = updatedUser
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
