import SwiftUI
import PhotosUI
import FirebaseAuth

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authVM: AuthViewModel

    @AppStorage("themePreference") private var themePreferenceRaw: String = ThemePreference.system.rawValue

    @State private var displayName: String = ""
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var themePreference: ThemePreference {
        ThemePreference(rawValue: themePreferenceRaw) ?? .system
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Profile Photo")) {
                    HStack(spacing: 12) {
                        avatar
                        PhotosPicker(selection: $selectedItem, matching: .images, photoLibrary: .shared()) {
                            Label("Choose Photo", systemImage: "photo")
                        }
                        .onChange(of: selectedItem) { newItem in
                            Task {
                                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                    selectedImageData = data
                                }
                            }
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
                        if isSaving { ProgressView() } else { Text("Save").bold() }
                    }
                    .disabled(isSaving || (displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedImageData == nil))
                }
            }
            .onAppear {
                displayName = authVM.user?.displayName ?? (Auth.auth().currentUser?.displayName ?? "")
            }
        }
    }

    @ViewBuilder
    private var avatar: some View {
        Group {
            if let data = selectedImageData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable().scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
            } else if let urlStr = authVM.user?.photoURL, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty: Circle().fill(Color(.tertiarySystemFill)).frame(width: 64, height: 64).overlay { ProgressView() }
                    case .success(let img): img.resizable().scaledToFill().frame(width: 64, height: 64).clipShape(Circle())
                    case .failure: placeholder
                    @unknown default: placeholder
                    }
                }
            } else {
                placeholder
            }
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
            if let data = selectedImageData, let uid = Auth.auth().currentUser?.uid {
                let url = try await StorageService().uploadProfileImage(data: data, for: uid)
                await authVM.updatePhotoURL(url)
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
