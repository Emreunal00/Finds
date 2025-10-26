import SwiftUI

struct FavoritesListView: View {
    enum SortOption: String, CaseIterable, Identifiable {
        case addedNewestFirst = "Newest first"
        case addedOldestFirst = "Oldest first"
        case titleAZ = "Title A–Z"
        case titleZA = "Title Z–A"
        case yearNewestFirst = "Year ↓"
        case yearOldestFirst = "Year ↑"
        case ratingHighFirst = "Rating ↓"
        case ratingLowFirst = "Rating ↑"

        var id: String { rawValue }
    }

    @EnvironmentObject var authVM: AuthViewModel
    @State private var movies: [Movie] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var sort: SortOption = .addedNewestFirst

    // Eklenme sırası referansı (typed entries)
    @State private var originalEntries: [WatchedEntry] = []
    // TMDb’de bulunmayanlar (404) için bilgi
    @State private var invalid: [WatchedEntry] = []

    private let service: MovieServicing = MovieService()

    private var entriesRaw: [WatchedEntry] {
        guard let u = authVM.user else { return [] }
        if !u.favoritesEntries.isEmpty {
            return u.favoritesEntries
        } else {
            // legacy fallback: favoritesIDs -> movie
            return u.favoritesIDs.map { WatchedEntry(id: $0, type: "movie") }
        }
    }

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
                if !invalid.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Some items are no longer available.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Unavailable items were hidden. You can refresh to update your list.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(sortedMovies()) { movie in
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
        .navigationTitle("All Favorites")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(SortOption.allCases) { opt in
                            Text(opt.rawValue).tag(opt)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                }
            }
        }
        .task { await loadAll() }
        .onChange(of: authVM.listsVersion) { _ in Task { await loadAll() } }
    }

    // MARK: - Data loading

    private func loadAll() async {
        let esRaw = entriesRaw
        guard !esRaw.isEmpty else {
            movies = []
            originalEntries = []
            invalid = []
            return
        }

        originalEntries = esRaw
        let newestFirst = Array(esRaw.reversed())

        isLoading = true
        errorMessage = nil
        invalid = []
        defer { isLoading = false }

        // Non-throwing group: tekil hataları atla, 404’leri tespit et
        let fetched: [Movie] = await withTaskGroup(of: (WatchedEntry, Movie?).self) { group -> [Movie] in
            for entry in newestFirst {
                group.addTask {
                    do {
                        if entry.type.lowercased() == "movie" {
                            let m = try await service.fetchMovieBasic(id: entry.id)
                            return (entry, m)
                        } else {
                            let tv = try await service.fetchTVBasic(id: entry.id)
                            return (entry, tv)
                        }
                    } catch {
                        let ns = error as NSError
                        if ns.domain == "TMDBHTTP", ns.code == 404 {
                            print("[FavoritesListView] TMDB 404 for id=\(entry.id) type=\(entry.type)")
                        } else {
                            print("[FavoritesListView] fetch failed for id=\(entry.id):", error.localizedDescription)
                        }
                        return (entry, nil)
                    }
                }
            }
            var items: [(WatchedEntry, Movie?)] = []
            while let next = await group.next() { items.append(next) }

            let map = Dictionary(uniqueKeysWithValues: items.compactMap { pair in
                if let movie = pair.1 { return (pair.0.id, movie) }
                return nil
            })
            let invalidEntries = newestFirst.filter { map[$0.id] == nil }
            if !invalidEntries.isEmpty {
                await MainActor.run { self.invalid = invalidEntries }
            }
            return newestFirst.compactMap { map[$0.id] }
        }
        movies = fetched
    }

    // MARK: - Sorting

    private func sortedMovies() -> [Movie] {
        switch sort {
        case .addedNewestFirst:
            let order = Array(originalEntries.reversed()).map { $0.id }
            let map = Dictionary(uniqueKeysWithValues: movies.map { ($0.id, $0) })
            return order.compactMap { map[$0] }
        case .addedOldestFirst:
            let order = originalEntries.map { $0.id }
            let map = Dictionary(uniqueKeysWithValues: movies.map { ($0.id, $0) })
            return order.compactMap { map[$0] }
        case .titleAZ:
            return movies.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .titleZA:
            return movies.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        case .yearNewestFirst:
            return movies.sorted { $0.year > $1.year }
        case .yearOldestFirst:
            return movies.sorted { $0.year < $1.year }
        case .ratingHighFirst:
            return movies.sorted { $0.rating > $1.rating }
        case .ratingLowFirst:
            return movies.sorted { $0.rating < $1.rating }
        }
    }

    // MARK: - Poster helpers

    @ViewBuilder
    private func poster(for movie: Movie) -> some View {
        if let url = movie.posterURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ZStack { Color(.tertiarySystemFill); ProgressView() }
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    placeholder
                @unknown default:
                    placeholder
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
            Image(systemName: "film")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
        }
    }
}
