import SwiftUI

struct WatchlistListView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var movies: [Movie] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    private let service: MovieServicing = MovieService()

    var body: some View {
        List {
            if isLoading {
                HStack { Spacer(); ProgressView("Loading…"); Spacer() }
            } else if let err = errorMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Failed to load").font(.headline)
                    Text(err).font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                ForEach(movies) { movie in
                    NavigationLink { MovieDetailView(movie: movie) } label: {
                        HStack(spacing: 12) {
                            poster(for: movie)
                                .frame(width: 50, height: 75)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(movie.title).font(.headline)
                                HStack(spacing: 8) {
                                    if movie.year > 0 { Text(String(movie.year)) }
                                    if movie.rating > 0 {
                                        let percent = Int(round(movie.rating * 20))
                                        Text("\(percent)%").foregroundStyle(ScoreColor.color(for: percent))
                                    }
                                }
                                .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
        .navigationTitle("All Watchlist")
        .task { await loadAll() }
        .onChange(of: authVM.listsVersion) { _ in Task { await loadAll() } }
    }

    private func loadAll() async {
        guard let ids = authVM.user?.watchlistIDs, !ids.isEmpty else {
            movies = []
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let fetched: [Movie] = try await withThrowingTaskGroup(of: (Int, Movie).self) { group in
                for id in ids {
                    group.addTask {
                        let m = try await service.fetchMovieBasic(id: id)
                        return (id, m)
                    }
                }
                var items: [(Int, Movie)] = []
                while let next = try await group.next() { items.append(next) }
                let map = Dictionary(uniqueKeysWithValues: items)
                return ids.compactMap { map[$0] }
            }
            movies = fetched
        } catch {
            errorMessage = error.localizedDescription
            movies = []
        }
    }

    @ViewBuilder
    private func poster(for movie: Movie) -> some View {
        if let url = movie.posterURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty: ZStack { Color(.tertiarySystemFill); ProgressView() }
                case .success(let image): image.resizable().scaledToFill()
                case .failure: placeholder
                @unknown default: placeholder
                }
            }
        } else if !movie.posterName.isEmpty {
            Image(movie.posterName).resizable().scaledToFill()
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Color(.tertiarySystemFill)
            Image(systemName: "film").font(.system(size: 16)).foregroundStyle(.secondary)
        }
    }
}
