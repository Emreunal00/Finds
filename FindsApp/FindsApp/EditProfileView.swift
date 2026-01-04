import SwiftUI
import FirebaseAuth

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authVM: AuthViewModel

    @AppStorage("themePreference") private var themePreferenceRaw: String = ThemePreference.system.rawValue

    @State private var displayName: String = ""
    @State private var selectedAvatarID: String?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingSignOutConfirm = false

    private let availableAvatars: [String] = (1...15).map { "avatar\($0)" }

    private var themePreference: ThemePreference {
        ThemePreference(rawValue: themePreferenceRaw) ?? .system
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
                                        Image(id)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 56, height: 56)
                                            .clipShape(Circle())
                                            .overlay(
                                                Circle().stroke(selectedAvatarID == id ? Color.accentColor : .clear, lineWidth: 3)
                                            )
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
                    Picker("Appearance", selection: $themePreferenceRaw) {
                        ForEach(ThemePreference.allCases) { opt in
                            Text(opt.displayName).tag(opt.rawValue)
                        }
                    }
                }

                if let err = errorMessage {
                    Section {
                        Text(err)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
                
                Section {
                    Button(role: .destructive) {
                        showingSignOutConfirm = true
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            .frame(maxWidth: .infinity, alignment: .center)
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
                displayName = authVM.user?.displayName ?? (Auth.auth().currentUser?.displayName ?? "")
                if let urlStr = authVM.user?.photoURL, urlStr.hasPrefix("avatar://") { selectedAvatarID = String(urlStr.dropFirst("avatar://".count)) }
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
        } else if let urlStr = authVM.user?.photoURL {
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

        do {
            if let id = selectedAvatarID {
                let urlStr = "avatar://" + id
                await authVM.updatePhotoURL(urlStr)
            }

            let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed != (authVM.user?.displayName ?? "") {
                await authVM.updateDisplayName(trimmed)
            }

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
