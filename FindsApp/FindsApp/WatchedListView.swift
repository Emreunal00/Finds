import Combine
import Observation
import SwiftUI

private final class WatchedRatingsCache: ObservableObject {
    static let shared = WatchedRatingsCache()
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

    // Original entries order (for added order)
    @State private var originalEntries: [WatchedEntry] = []
    @StateObject private var ratingsCache = WatchedRatingsCache.shared

    @State private var pendingDeletionMovie: Movie? = nil
    @State private var showingDeletionConfirm = false

    private let service: MovieServicing = MovieService()

    // Updated to use currentProfile instead of user for watchedEntries
    private var entriesRaw: [WatchedEntry] {
        guard let profile = authVM.currentProfile else { return [] }
        if !profile.watchedEntries.isEmpty {
            return profile.watchedEntries
        } else {
            // Legacy fallback: deprecated, kept for migration only
            return authVM.user?.watchedIDs.map { WatchedEntry(id: $0, type: "movie") } ?? []
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
                        NavigationLink { MovieDetailView(movie: movie) } label: { EmptyView() }
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
        // Reload when listsVersion changes
        .onChange(of: authVM.listsVersion) { _ in Task { await loadAll() } }
        // Reload when currentProfile changes
        .onChange(of: authVM.currentProfile) { _ in Task { await loadAll() } }
        .overlay {
            if showingDeletionConfirm, let movie = pendingDeletionMovie {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    VStack(spacing: 16) {
                        Text("Remove from Watched?")
                            .font(.headline)
                        Text("This will remove \(movie.title) from your Watched list.")
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
                                removeFromWatched(movie)
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

    // MARK: - Deletion

    private func removeFromWatched(_ movie: Movie) {
        // Optimistically update local UI
        movies.removeAll { $0.id == movie.id }
        originalEntries.removeAll { $0.id == movie.id }

        // Persist the change (AuthViewModel handles toggling)
        Task { @MainActor in
            await authVM.toggleWatched(movieID: movie.id, type: (movie.mediaType ?? "movie"))
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
