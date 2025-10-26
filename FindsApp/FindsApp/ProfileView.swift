import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authVM: AuthViewModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(displayName)
                                .font(.headline)
                            Text(email)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let u = authVM.user {
                    Section("Listelerim") {
                        HStack {
                            Label("Favoriler", systemImage: "heart.fill")
                                .foregroundStyle(.pink)
                            Spacer()
                            Text("\(u.favoritesIDs.count)")
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Label("Watchlist", systemImage: "bookmark.fill")
                                .foregroundStyle(.blue)
                            Spacer()
                            Text("\(u.watchlistIDs.count)")
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Label("İzlendi", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Spacer()
                            Text("\(u.watchedIDs.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        authVM.signOut()
                    } label: {
                        Label("Çıkış Yap", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Profil")
        }
    }

    private var displayName: String {
        if let n = authVM.user?.displayName, !n.isEmpty { return n }
        return "Kullanıcı"
    }

    private var email: String {
        authVM.user?.email ?? "-"
    }
}

#Preview {
    ProfileView()
        .environmentObject(AuthViewModel())
}

