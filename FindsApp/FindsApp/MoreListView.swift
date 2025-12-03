import SwiftUI

struct MoreListView: View {
    enum Kind {
        case trendingMovies
        case suggestedMovies
        case trendingTV
        case suggestedTV

        var title: String {
            switch self {
            case .trendingMovies: return "Trending movies"
            case .suggestedMovies: return "Top picks for you"
            case .trendingTV:     return "Trending shows"
            case .suggestedTV:    return "Suggested shows"
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
    @State private var movies: [Movie] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var sort: SortOption = .popularityDesc

    private let service: MovieServicing = MovieService()

    var body: some View {
        List {
            if isLoading {
                HStack { Spacer(); ProgressView("Loading…"); Spacer() }
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
                        MovieDetailView(movie: movie)
                    } label: {
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
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            var result: [Movie] = []
            var page = 1
            while result.count < 250 && page <= 20 { // güvenli üst sınır
                let batch: [Movie]
                switch kind {
                case .trendingMovies:
                    batch = try await service.getTrending(page: page)
                case .suggestedMovies:
                    batch = try await service.getSuggestions(page: page)
                case .trendingTV:
                    batch = try await service.getTrendingTV(page: page)
                case .suggestedTV:
                    batch = try await service.getSuggestionsTV(page: page)
                }
                if batch.isEmpty { break }
                result.append(contentsOf: batch)
                page += 1
            }
            if result.count > 250 { result = Array(result.prefix(250)) }
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
