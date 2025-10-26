import SwiftUI
import Combine

struct ContentView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @StateObject private var homeVM = HomeViewModel()
    // Removed user lists from the home screen; they will load on the profile screen
    @State private var showProfile = false

    var body: some View {
        NavigationStack {
            Group {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Keep only trending and suggestions on the home screen
                        Group {
                            if homeVM.isLoading && homeVM.trending.isEmpty && homeVM.suggestions.isEmpty {
                                ProgressView("Loading…")
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else if let err = homeVM.error, homeVM.trending.isEmpty && homeVM.suggestions.isEmpty {
                                VStack(spacing: 12) {
                                    Text("Failed to load")
                                        .font(.headline)
                                    Text(err)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                    Button("Retry") {
                                        Task { await homeVM.load() }
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding()
                            } else {
                                VStack(alignment: .leading, spacing: 24) {
                                    if !homeVM.trending.isEmpty {
                                        SectionHeader(title: "Trending")
                                        PosterHScroll(movies: homeVM.trending)
                                    }

                                    if !homeVM.suggestions.isEmpty {
                                        SectionHeader(title: "Suggestions")
                                        PosterHScroll(movies: homeVM.suggestions)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                }
            }
            .navigationTitle("Finds")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        if let name = authVM.user?.displayName, !name.isEmpty {
                            Text("Signed in as \(name)")
                        } else if let email = authVM.user?.email {
                            Text("Signed in as \(email)")
                        }

                        Button {
                            showProfile = true
                        } label: {
                            Label("Profile", systemImage: "person")
                        }

                        Button(role: .destructive) {
                            authVM.signOut()
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "person.circle")
                    }
                }
            }
            .navigationDestination(isPresented: $showProfile) {
                ProfileView()
                    .environmentObject(authVM)
            }
            .task {
                if homeVM.trending.isEmpty && homeVM.suggestions.isEmpty {
                    await homeVM.load()
                }
            }
            .refreshable {
                await homeVM.load()
            }
            .background(
                LinearGradient(colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                               startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            )
        }
    }
}

// MARK: - Section Header

private struct SectionHeader: View {
    let title: String
    var body: some View {
        HStack {
            Text(title)
                .font(.title3).bold()
            Spacer()
        }
    }
}

private struct PosterHScroll: View {
    let movies: [Movie]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(movies) { movie in
                    NavigationLink {
                        MovieDetailView(movie: movie)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            poster(for: movie)
                                .frame(width: 120, height: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.black.opacity(0.06))
                                }
                            Text(movie.title)
                                .font(.footnote)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .frame(width: 120, alignment: .leading)
                            HStack(spacing: 6) {
                                if movie.year > 0 {
                                    Text(String(movie.year))
                                }
                                if movie.rating > 0 {
                                    let percent = Int(round(movie.rating * 20))
                                    Text("\(percent)%")
                                        .foregroundStyle(ScoreColor.color(for: percent))
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func poster(for movie: Movie) -> some View {
        if let url = movie.posterURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ZStack {
                        Color(.tertiarySystemFill)
                        ProgressView()
                    }
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
        } else if !movie.posterName.isEmpty {
            Image(movie.posterName)
                .resizable()
                .scaledToFill()
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Color(.tertiarySystemFill)
            Image(systemName: "film")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthViewModel())
}
