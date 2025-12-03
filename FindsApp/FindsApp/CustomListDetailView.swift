import SwiftUI
import FirebaseFirestore
import Combine

private final class FavoritesRatingsCache: ObservableObject {
    static let shared = FavoritesRatingsCache()
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

struct CustomListDetailView: View {
    let list: ProfileCustomUserList
    @EnvironmentObject var authVM: AuthViewModel

    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var movies: [Movie] = []
    @StateObject private var ratingsCache = FavoritesRatingsCache.shared

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

    @State private var sort: SortOption = .addedNewestFirst

    // Eklenme sırası referansı
    @State private var originalOrderIDs: [Int] = []

    private let service: MovieServicing = MovieService()

    var body: some View {
        Group {
            if isLoading {
                VStack { ProgressView("Loading…") }.frame(maxWidth: .infinity)
            } else if let err = errorMessage {
                VStack(spacing: 8) {
                    Text("Failed to load").font(.headline)
                    Text(err).font(.footnote).foregroundStyle(.secondary)
                    Button("Retry") { Task { await loadItems() } }.buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
            } else if movies.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "text.badge.plus").font(.system(size: 28)).foregroundStyle(.secondary)
                    Text("No items in this list").font(.headline)
                    Text("Use 'Add to List' in a movie to include it here.").font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(sortedMovies()) { movie in
                        NavigationLink { MovieDetailView(movie: movie) } label: {
                            row(for: movie)
                        }
                        .onAppear { ratingsCache.loadIfNeeded(for: movie) }
                    }
                }
                .listStyle(.plain)
                .refreshable { await loadItems() }
            }
        }
        .navigationTitle(list.name)
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
        .task { await loadItems() }
    }

    private func row(for movie: Movie) -> some View {
        HStack(spacing: 12) {
            poster(for: movie)
                .frame(width: 60, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        .padding(.vertical, 6)
    }

    // MARK: - Sorting
    private func sortedMovies() -> [Movie] {
        switch sort {
        case .addedNewestFirst:
            let map = Dictionary(uniqueKeysWithValues: movies.map { ($0.id, $0) })
            return originalOrderIDs.compactMap { map[$0] }
        case .addedOldestFirst:
            let reversed = Array(originalOrderIDs.reversed())
            let map = Dictionary(uniqueKeysWithValues: movies.map { ($0.id, $0) })
            return reversed.compactMap { map[$0] }
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
            Image(systemName: "film").font(.system(size: 16)).foregroundStyle(.secondary)
        }
    }

    private func loadItems() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        guard let uid = authVM.user?.id else {
            errorMessage = "Not signed in"
            movies = []
            return
        }

        do {
            let db = Firestore.firestore()
            let itemsRef = db.collection("users").document(uid)
                .collection("lists").document(list.id)
                .collection("items")
                .order(by: "addedAt", descending: true)

            let snap = try await itemsRef.getDocuments()
            let items = snap.documents.compactMap { doc -> (Int, String)? in
                let data = doc.data()
                guard let id = data["movieId"] as? Int, let type = data["type"] as? String else { return nil }
                return (id, type)
            }
            self.originalOrderIDs = items.map { $0.0 }

            let fetched: [Movie] = await withTaskGroup(of: (Int, Movie?).self) { group -> [Movie] in
                for (id, type) in items {
                    group.addTask {
                        do {
                            if type.lowercased() == "movie" {
                                let m = try await service.fetchMovieBasic(id: id)
                                return (id, m)
                            } else {
                                let tv = try await service.fetchTVBasic(id: id)
                                return (id, tv)
                            }
                        } catch {
                            return (id, nil)
                        }
                    }
                }
                var results: [(Int, Movie?)] = []
                while let next = await group.next() { results.append(next) }
                let map = Dictionary(uniqueKeysWithValues: results)
                let ordered = items.compactMap { map[$0.0] ?? nil }
                return ordered.compactMap { $0 }
            }
            movies = fetched
            for m in movies { ratingsCache.loadIfNeeded(for: m) }
        } catch {
            errorMessage = error.localizedDescription
            movies = []
        }
    }
}

#Preview {
    NavigationStack {
        CustomListDetailView(list: ProfileCustomUserList(id: "abc", name: "My List"))
            .environmentObject(AuthViewModel())
    }
}

