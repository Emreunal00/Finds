import SwiftUI
import Combine

private final class MoreRatingsCache: ObservableObject {
    static let shared = MoreRatingsCache()
    @Published private(set) var averages: [String: Double] = [:] 
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

struct MoreListView: View {
    enum Kind {
        case trendingMovies
        case suggestedMovies
        case trendingTV
        case suggestedTV
        case trendingBooks
        case suggestedBooks

        var title: String {
            switch self {
            case .trendingMovies: return "Trending movies"
            case .suggestedMovies: return "Top picks for you"
            case .trendingTV:     return "Trending shows"
            case .suggestedTV:    return "Suggested shows"
            case .trendingBooks:  return "Popular books"
            case .suggestedBooks: return "Recommended books"
            }
        }

        var isSuggested: Bool {
            switch self {
            case .suggestedMovies, .suggestedTV, .suggestedBooks:
                return true
            case .trendingMovies, .trendingTV, .trendingBooks:
                return false
            }
        }
    }

    enum SortOption: String, CaseIterable, Identifiable {
        case popularityDesc = "Popularity ↓"
        case ratingDesc = "Rating ↓"
        case ratingAsc = "Rating ↑"
        case titleAZ = "Title A–Z"
        case titleZA = "Title Z–A"
        case yearDesc = "Year ↓"
        case yearAsc = "Year ↑"

        var id: String { rawValue }
    }

    let kind: Kind
    @StateObject private var ratingsCache = MoreRatingsCache.shared
    @State private var movies: [Movie] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var sort: SortOption = .popularityDesc

    private let service: MovieServicing = MovieService()
    
    @EnvironmentObject private var authVM: AuthViewModel
    private let recommendations = RecommendationsService()

    var body: some View {
        List {
            if isLoading {
                HStack { Spacer(); CustomLoadingView(message: "Loading…"); Spacer() }
            } else if let err = errorMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Failed to load").font(.headline)
                    Text(err).font(.footnote).foregroundStyle(.secondary)
                    Button("Retry") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 4)
                }
            } else {
                ForEach(sortedMovies()) { movie in
                    NavigationLink {
                        MediaDetailDestination(item: movie)
                    } label: {
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
                    }
                    .onAppear { ratingsCache.loadIfNeeded(for: movie) }
                }
            }
        }
        .navigationTitle(kind.title)
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
                    Label("Sort", systemImage: "arrow.up.arrow.down.circle")
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: authVM.currentProfile?.id) { _, _ in
            Task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            var result: [Movie] = []
            var page = 1
            while result.count < 250 && page <= 20 { 
                let batch: [Movie]
                switch kind {
                case .trendingMovies:
                    batch = try await service.getTrending(page: page)
                case .suggestedMovies:
                    if page == 1, let uid = authVM.user?.id, !uid.isEmpty, let profileID = authVM.currentProfile?.id {
                        batch = try await recommendations.fetchRecommendedMovies(userID: uid, profileID: profileID)
                    } else {
                        batch = [] 
                    }
                case .trendingTV:
                    batch = try await service.getTrendingTV(page: page)
                case .suggestedTV:
                    if page == 1, let uid = authVM.user?.id, !uid.isEmpty, let profileID = authVM.currentProfile?.id {
                        batch = try await recommendations.fetchRecommendedShows(userID: uid, profileID: profileID)
                    } else {
                        batch = [] 
                    }
                case .trendingBooks:
                    batch = await BookCatalog.trendingBooks(page: page)
                case .suggestedBooks:
                    if page == 1, let uid = authVM.user?.id, !uid.isEmpty, let profileID = authVM.currentProfile?.id {
                        batch = try await recommendations.fetchRecommendedBooks(userID: uid, profileID: profileID)
                    } else {
                        batch = []
                    }
                }
                if batch.isEmpty { break }
                result.append(contentsOf: batch)
                page += 1
            }
            if result.count > 250 { result = Array(result.prefix(250)) }
            if kind.isSuggested, let profile = authVM.currentProfile {
                result = result.filter { profile.shouldShowAsRecommendation($0) }
            }
            movies = result
        } catch {
            errorMessage = error.localizedDescription
            movies = []
        }
    }

    private func sortedMovies() -> [Movie] {
        switch sort {
        case .popularityDesc:
            return movies.sorted {
                let l = $0.popularity ?? -1
                let r = $1.popularity ?? -1
                if l != r { return l > r }
                if $0.rating != $1.rating { return $0.rating > $1.rating }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        case .ratingDesc:
            return movies.sorted {
                if $0.rating != $1.rating { return $0.rating > $1.rating }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        case .ratingAsc:
            return movies.sorted {
                if $0.rating != $1.rating { return $0.rating < $1.rating }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        case .titleAZ:
            return movies.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .titleZA:
            return movies.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        case .yearDesc:
            return movies.sorted { $0.year > $1.year }
        case .yearAsc:
            return movies.sorted { $0.year < $1.year }
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
            ZStack {
                Color(.tertiarySystemFill)
                Image(systemName: BookCatalog.symbolName(for: movie))
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            Color(.tertiarySystemFill)
            Image(systemName: "film").font(.system(size: 16)).foregroundStyle(.secondary)
        }
    }
}
