import Combine
import Observation
import SwiftUI

private final class WatchlistRatingsCache: ObservableObject {
    
    static let shared = WatchlistRatingsCache()
    @Published private(set) var averages: [String: Double] = [:] // key: "type:id"
    private var ongoing: Set<String> = []

    func key(for movie: Movie) -> String { "\((movie.mediaType ?? "movie").lowercased()):\(movie.id)" }
    func average(for movie: Movie) -> Double? { averages[key(for: movie)] }

    func loadIfNeeded(for movie: Movie) {
        let k = key(for: movie)
        if averages[k] != nil || ongoing.contains(k) { return }
        ongoing.insert(k)
        Task { [weak self] in
            let repo = RatingsRepository()
            let type = (movie.mediaType ?? "movie").lowercased()
            do {
                if let agg = try await repo.fetchAggregate(movieID: movie.id, type: type) {
                    await MainActor.run { self?.averages[k] = agg.average; self?.ongoing.remove(k) }
                } else {
                    await MainActor.run { self?.averages[k] = 0; self?.ongoing.remove(k) }
                }
            } catch {
                await MainActor.run { self?.averages[k] = 0; self?.ongoing.remove(k) }
            }
        }
    }
}

struct WatchlistListView: View {
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

    @State private var originalEntries: [WatchedEntry] = []
    @State private var invalid: [WatchedEntry] = []

    @State private var pendingDeletionMovie: Movie? = nil
    @State private var showingDeletionConfirm = false

    @StateObject private var ratingsCache = WatchlistRatingsCache.shared

    private let service: MovieServicing = MovieService()

    // Use watchlistEntries from currentProfile instead of user, fallback to legacy user.watchlistIDs for migration only
    private var entriesRaw: [WatchedEntry] {
        guard let profile = authVM.currentProfile else { return [] }
        if !profile.watchlistEntries.isEmpty {
            return profile.watchlistEntries
        } else {
            // Legacy fallback: deprecated, kept for migration only
            return authVM.user?.watchlistIDs.map { WatchedEntry(id: $0, type: "movie") } ?? []
        }
    }

    var body: some View {
        List {
            if isLoading {
                HStack { Spacer(); CustomLoadingView(message: "Loading…"); Spacer() }
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
                    ZStack {
                        HStack(spacing: 12) {
                            poster(for: movie)
                                .frame(width: 50, height: 75)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(movie.title).font(.headline)
                                HStack(spacing: 8) {
                                    if movie.year > 0 { Text(String(movie.year)) }
                                    if let avg = ratingsCache.average(for: movie) {
                                        Text(String(format: "%.1f / 5", avg))
                                    }
                                }
                                .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        NavigationLink { MediaDetailDestination(item: movie) } label: { EmptyView() }
                            .opacity(0)
                    }
                    .onAppear { ratingsCache.loadIfNeeded(for: movie) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            pendingDeletionMovie = movie
                            showingDeletionConfirm = true
                        } label: {
                            Label("Remove", systemImage: "trash.fill")
                        }
                        .tint(.red)
                    }
                }
            }
        }
        .navigationTitle("All Watchlist")
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
        // Reload watchlist when the current profile changes
        .onChange(of: authVM.currentProfile) { _ in Task { await loadAll() } }
        .overlay {
            if showingDeletionConfirm, let movie = pendingDeletionMovie {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    VStack(spacing: 16) {
                        Text("Remove from Watchlist?")
                            .font(.headline)
                        Text("This will remove \(movie.title) from your Watchlist.")
                            .multilineTextAlignment(.center)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        HStack {
                            Button("Cancel") {
                                showingDeletionConfirm = false
                                pendingDeletionMovie = nil
                            }
                            .buttonStyle(.bordered)
                            Spacer()
                            Button("Remove") {
                                removeFromWatchlist(movie)
                                showingDeletionConfirm = false
                                pendingDeletionMovie = nil
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

    private func loadAll() async {
        let esRaw = entriesRaw
        guard !esRaw.isEmpty else {
            movies = []; originalEntries = []; invalid = []; return
        }

        originalEntries = esRaw
        let newestFirst = Array(esRaw.reversed())

        isLoading = true
        errorMessage = nil
        invalid = []
        defer { isLoading = false }

        let fetched: [Movie] = await withTaskGroup(of: (WatchedEntry, Movie?).self) { group -> [Movie] in
            for entry in newestFirst {
                group.addTask {
                    do {
                        let media = try await BookCatalog.fetchMedia(id: entry.id, type: entry.type, externalContentID: entry.externalID, service: service)
                        return (entry, media)
                    } catch {
                        let ns = error as NSError
                        if ns.domain == "TMDBHTTP", ns.code == 404 {
                            print("[WatchlistListView] TMDB 404 for id=\(entry.id) type=\(entry.type)")
                        } else {
                            print("[WatchlistListView] fetch failed for id=\(entry.id):", error.localizedDescription)
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

    // MARK: - Deletion

    private func removeFromWatchlist(_ movie: Movie) {
        // Optimistically update local UI
        movies.removeAll { $0.id == movie.id }
        originalEntries.removeAll { $0.id == movie.id }

        // Persist the change (AuthViewModel handles toggling)
        Task { @MainActor in
            // Use currentProfile context for removal
            await authVM.toggleWatchlist(movieID: movie.id, mediaType: (movie.mediaType ?? "movie"), externalContentID: movie.externalContentID)
        }
    }

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
            return movies.sorted { (ratingsCache.average(for: $0) ?? 0) > (ratingsCache.average(for: $1) ?? 0) }
        case .ratingLowFirst:
            return movies.sorted { (ratingsCache.average(for: $0) ?? 0) < (ratingsCache.average(for: $1) ?? 0) }
        }
    }

    @ViewBuilder
    private func poster(for movie: Movie) -> some View {
        if let url = movie.posterURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty: ZStack { Color(.tertiarySystemFill); CustomLoadingView() }
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
