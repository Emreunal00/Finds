import SwiftUI
import FirebaseAuth

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var themeStore: ThemeStore

    @State private var displayName: String = ""
    @State private var selectedAvatarID: String?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingSignOutConfirm = false
    @State private var showingDeleteProfileConfirm = false

    private let availableAvatars: [String] = (1...15).map { "avatar\($0)" }

    private var canDeleteCurrentProfile: Bool {
        guard let user = authVM.user else { return false }
        return user.profiles.count > 1 && authVM.currentProfile != nil
    }

    private var deleteProfileHelpText: String {
        guard let user = authVM.user else { return "No signed-in user found." }
        guard authVM.currentProfile != nil else { return "No active profile selected." }
        if user.profiles.count <= 1 { return "At least one profile must remain on the account." }
        return "This profile will be removed from the current account."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Avatar")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            avatar
                            Text("Current selection")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 12) {
                                ForEach(availableAvatars, id: \.self) { id in
                                    Button {
                                        selectedAvatarID = id
                                    } label: {
                                        avatarOption(id: id)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(Text("Select avatar \(id)"))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section(header: Text("Display Name")) {
                    TextField("Your name", text: $displayName)
                        .textInputAutocapitalization(.words)
                }

                Section(header: Text("Theme")) {
                    Picker("Appearance", selection: $themeStore.preference) {
                        ForEach(ThemePreference.allCases) { opt in
                            Text(opt.displayName).tag(opt)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if let err = errorMessage {
                    Section {
                        Text(err)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                Section("Profile Actions") {
                    Button(role: .destructive) {
                        handleDeleteTap()
                    } label: {
                        Label("Delete Profile", systemImage: "trash")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Text(deleteProfileHelpText)
                        .font(.footnote)
                        .foregroundColor(canDeleteCurrentProfile ? .secondary : .orange)
                }
                
                Section("Account") {
                    Button(role: .destructive) {
                        showingSignOutConfirm = true
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await saveChanges() }
                    } label: {
                        if isSaving {Text("Save")} else { Text("Save")}
                    }
                    .disabled(isSaving || (displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedAvatarID == nil))
                }
            }
            .onAppear {
                displayName = authVM.currentProfile?.displayName ?? (Auth.auth().currentUser?.displayName ?? "")
                if let urlStr = authVM.currentProfile?.photoURL, urlStr.hasPrefix("avatar://") { selectedAvatarID = String(urlStr.dropFirst("avatar://".count)) }
            }
            .preferredColorScheme(themeStore.preference.colorScheme)
            .overlay {
                if showingDeleteProfileConfirm {
                    ZStack {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                        VStack(spacing: 16) {
                            Text("Delete Profile?")
                                .font(.headline)
                            Text("This removes the current profile and its profile-specific lists from this account.")
                                .multilineTextAlignment(.center)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            HStack {
                                Button("Cancel") {
                                    showingDeleteProfileConfirm = false
                                }
                                .buttonStyle(.bordered)
                                Spacer()
                                Button("Delete") {
                                    showingDeleteProfileConfirm = false
                                    Task { await deleteCurrentProfile() }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                            }
                        }
                        .padding(24)
                        .frame(maxWidth: 320)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(.systemBackground))
                        )
                        .padding(.horizontal, 40)
                    }
                }
            }
            .overlay {
                if showingSignOutConfirm {
                    ZStack {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                        VStack(spacing: 16) {
                            Text("Sign Out")
                                .font(.headline)
                            Text("Are you sure you want to sign out?")
                                .multilineTextAlignment(.center)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            HStack {
                                Button("Cancel") {
                                    showingSignOutConfirm = false
                                }
                                .buttonStyle(.bordered)
                                Spacer()
                                Button("Sign Out") {
                                    authVM.signOut()
                                    showingSignOutConfirm = false
                                    dismiss()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                            }
                        }
                        .padding(24)
                        .frame(maxWidth: 320)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(.systemBackground))
                        )
                        .padding(.horizontal, 40)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let id = selectedAvatarID {
            Image(id)
                .resizable().scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(Circle())
        } else if let urlStr = authVM.currentProfile?.photoURL {
            if urlStr.hasPrefix("avatar://") {
                let id = String(urlStr.dropFirst("avatar://".count))
                Image(id)
                    .resizable().scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
            } else if let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty: Circle().fill(Color(.tertiarySystemFill)).frame(width: 64, height: 64).overlay { CustomLoadingView() }
                    case .success(let img): img.resizable().scaledToFill().frame(width: 64, height: 64).clipShape(Circle())
                    case .failure: placeholder
                    @unknown default: placeholder
                    }
                }
            } else {
                placeholder
            }
        } else {
            placeholder
        }
    }

    private func avatarOption(id: String) -> some View {
        let strokeColor: Color = selectedAvatarID == id ? .accentColor : .clear

        return Image(id)
            .resizable()
            .scaledToFill()
            .frame(width: 56, height: 56)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(strokeColor, lineWidth: 3)
            }
    }

    private var placeholder: some View {
        Circle()
            .fill(Color(.tertiarySystemFill))
            .frame(width: 64, height: 64)
            .overlay {
                Image(systemName: "person.fill")
                    .foregroundStyle(.secondary)
            }
    }

    private func saveChanges() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        if let id = selectedAvatarID {
            let urlStr = "avatar://" + id
            await authVM.updatePhotoURL(urlStr)
        }

        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != (authVM.currentProfile?.displayName ?? "") {
            await authVM.updateDisplayName(trimmed)
        }

        dismiss()
    }

    private func deleteCurrentProfile() async {
        guard let profileID = authVM.currentProfile?.id, canDeleteCurrentProfile else { return }
        debugPrint("[EditProfile] deleteCurrentProfile tapped profileID=\(profileID)")
        do {
            try await authVM.deleteProfile(profileID)
            debugPrint("[EditProfile] deleteCurrentProfile success profileID=\(profileID)")
            dismiss()
        } catch {
            debugPrint("[EditProfile] deleteCurrentProfile failed profileID=\(profileID) error=\(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    private func handleDeleteTap() {
        guard canDeleteCurrentProfile else {
            errorMessage = deleteProfileHelpText
            debugPrint("[EditProfile] deleteCurrentProfile blocked reason=\(deleteProfileHelpText)")
            return
        }

        errorMessage = nil
        showingDeleteProfileConfirm = true
        debugPrint("[EditProfile] deleteCurrentProfile confirm requested")
    }
}
