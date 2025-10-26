import SwiftUI

struct WatchedListView: View {
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

    // Orijinal entries sırası (eklenme sırası için)
    @State private var originalEntries: [WatchedEntry] = []

    private let service: MovieServicing = MovieService()

    private var entriesRaw: [WatchedEntry] {
        guard let u = authVM.user else { return [] }
        if !u.watchedEntries.isEmpty {
            return u.watchedEntries
        } else {
            return u.watchedIDs.map { WatchedEntry(id: $0, type: "movie") }
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
        .navigationTitle("All Watched")
        .toolbar {
            Menu {
                Picker("Sort", selection: $sort) {
                    ForEach(SortOption.allCases) { opt in
                        Text(opt.rawValue).tag(opt)
                    }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down.circle")
            }
        }
        .task { await loadAll() }
        .onChange(of: authVM.listsVersion) { _ in Task { await loadAll() } }
    }

    private func loadAll() async {
        let esRaw = entriesRaw
        guard !esRaw.isEmpty else {
            movies = []
            originalEntries = []
            return
        }

        let newestFirst = Array(esRaw.reversed())
        originalEntries = esRaw

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let fetched: [Movie] = try await withThrowingTaskGroup(of: (Int, Movie?).self) { group in
                for entry in newestFirst {
                    group.addTask {
                        do {
                            if entry.type == "movie" {
                                let m = try await service.fetchMovieBasic(id: entry.id)
                                return (entry.id, m)
                            } else {
                                let tv = try await service.fetchTVBasic(id: entry.id)
                                return (entry.id, tv)
                            }
                        } catch {
                            return (entry.id, nil)
                        }
                    }
                }
                var items: [(Int, Movie?)] = []
                while let next = try await group.next() { items.append(next) }
                let map = Dictionary(uniqueKeysWithValues: items)
                let ordered = newestFirst.compactMap { map[$0.id] ?? nil }
                return ordered.compactMap { $0 }
            }
            movies = fetched
        } catch {
            errorMessage = error.localizedDescription
            movies = []
        }
    }

    private func sortedMovies() -> [Movie] {
        switch sort {
        case .addedNewestFirst:
            // newest-first: originalEntries.reversed()
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
