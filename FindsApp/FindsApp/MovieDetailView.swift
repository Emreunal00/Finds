import SwiftUI

struct MovieDetailView: View {
    let movie: Movie
    @EnvironmentObject var authVM: AuthViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerPoster
                titleSection
                actionRow
                metaSection
                if !movie.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(movie.summary)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .padding(.top, 4)
                }
                Spacer(minLength: 12)
            }
            .padding()
        }
        .navigationTitle(movie.title)
        .navigationBarTitleDisplayMode(.inline)
        .background(
            LinearGradient(
                colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                startPoint: .top,
                endPoint: .bottom
            ).ignoresSafeArea()
        )
    }

    private var isFavorite: Bool {
        guard let profile = authVM.user else { return false }
        return profile.favoritesIDs.contains(movie.id)
    }

    private var isInWatchlist: Bool {
        guard let profile = authVM.user else { return false }
        return profile.watchlistIDs.contains(movie.id)
    }

    private var isWatched: Bool {
        guard let profile = authVM.user else { return false }
        // Check typed entries first, then legacy
        if let entries = profile.watchedEntries as [WatchedEntry]? {
            if entries.contains(where: { $0.id == movie.id && $0.type == (movie.mediaType ?? "movie") }) {
                return true
            }
        }
        return profile.watchedIDs.contains(movie.id)
    }

    private var headerPoster: some View {
        Group {
            if let url = movie.posterURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ZStack { Color(.tertiarySystemFill); ProgressView() }
                    case .success(let image):
                        image.resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
                .frame(maxWidth: .infinity)
            } else if !movie.posterName.isEmpty {
                Image(movie.posterName)
                    .resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                placeholder
            }
        }
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(movie.title).font(.title2).bold()
            HStack(spacing: 8) {
                if movie.year > 0 { Text(String(movie.year)) }
                if movie.rating > 0 {
                    let percent = Int(round(movie.rating * 20))
                    Text("\(percent)%").font(.subheadline.weight(.semibold))
                        .foregroundStyle(ScoreColor.color(for: percent))
                }
                if let runtime = movie.durationMinutes {
                    Label("\(runtime) min", systemImage: "clock").symbolRenderingMode(.hierarchical)
                }
            }
            .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                Task { await authVM.toggleFavorite(movieID: movie.id) }
            } label: {
                Label(isFavorite ? "Favorited" : "Favorite",
                      systemImage: isFavorite ? "heart.fill" : "heart")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)
            .tint(isFavorite ? .pink : .secondary)
            .disabled(authVM.user == nil)

            Button {
                Task { await authVM.toggleWatchlist(movieID: movie.id) }
            } label: {
                Label(isInWatchlist ? "In Watchlist" : "Watchlist",
                      systemImage: isInWatchlist ? "bookmark.fill" : "bookmark")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)
            .tint(isInWatchlist ? .blue : .secondary)
            .disabled(authVM.user == nil)

            Button {
                let type = movie.mediaType ?? "movie"
                Task { await authVM.toggleWatched(movieID: movie.id, type: type) }
            } label: {
                Label(isWatched ? "Watched" : "Mark as Watched",
                      systemImage: isWatched ? "checkmark.circle.fill" : "checkmark.circle")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)
            .tint(isWatched ? .green : .secondary)
            .disabled(authVM.user == nil)
        }
        .font(.subheadline)
        .padding(.top, 4)
    }

    private var metaSection: some View {
        let readableGenres: [String] = movie.genres.map { token in
            if token.hasPrefix("#"), let id = Int(token.dropFirst()) { return "#\(id)" }
            return token
        }
        return Group {
            if !readableGenres.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(readableGenres, id: \.self) { g in
                            Text(g)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            Color(.tertiarySystemFill)
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Image(systemName: "film").font(.system(size: 40)).foregroundStyle(.secondary)
        }
    }
}

#Preview {
    let sample = Movie(
        id: 1,
        title: "Sample Movie",
        year: 2023,
        genres: ["#28", "#12"],
        posterName: "",
        rating: 4.2,
        summary: "This is a sample overview for the movie. It provides a brief description of the plot.",
        posterURL: URL(string: "https://image.tmdb.org/t/p/w500/abc123.jpg"),
        durationMinutes: 123,
        mediaType: "movie"
    )
    return NavigationStack {
        MovieDetailView(movie: sample)
            .environmentObject(AuthViewModel())
    }
}

