// SearchViewModel.swift
import Foundation
import Combine

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var keyword: String = ""
    @Published var selectedGenreID: Int?
    @Published var selectedYear: Int?
    @Published var results: [Movie] = []
    @Published var isLoading = false
    @Published var error: String?

    @Published var genres: [TMDBGenre] = []

    private let service: MovieServicing

    init(service: MovieServicing = MovieService()) {
        self.service = service
    }

    func loadGenres() async {
        print("[SearchVM] loadGenres start")
        do {
            genres = try await service.fetchGenres()
            print("[SearchVM] loadGenres success: \(genres.count) genres")
        } catch {
            print("[SearchVM] loadGenres failed:", error)
            // even if genres fail to load, search should still work
        }
    }

    func search() async {
        let q = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            print("[SearchVM] search aborted: empty query")
            results = []
            return
        }
        guard !isLoading else {
            print("[SearchVM] search skipped: already loading")
            return
        }

        isLoading = true
        error = nil
        print("[SearchVM] search start query='\(q)' year=\(selectedYear?.description ?? "nil") genreID=\(selectedGenreID?.description ?? "nil")")

        do {
            // BOTH MOVIE AND TV: search/multi (MovieService has fallback)
            var movies = try await service.searchMulti(query: q, page: 1)
            print("[SearchVM] search/multi returned \(movies.count) items")

            // Optional: client-side filters by year and genre
            if let year = selectedYear {
                let before = movies.count
                movies = movies.filter { $0.year == year }
                print("[SearchVM] year filter \(year): \(before) -> \(movies.count)")
            }
            if let gid = selectedGenreID {
                // Assumes Movie.genres contains "#<id>" tokens
                let token = "#\(gid)"
                let before = movies.count
                movies = movies.filter { $0.genres.contains(token) }
                print("[SearchVM] genre filter \(gid): \(before) -> \(movies.count)")
            }

            // Relevance scoring:
            // - Prefix match is stronger
            // - Substring match is weaker
            // - +1 if year matches
            // - Ties: rating desc, then alphabetical
            let tokens = q
                .lowercased()
                .split { $0.isWhitespace }
                .map(String.init)
                .filter { !$0.isEmpty }

            func score(for movie: Movie) -> Int {
                let title = movie.title.lowercased()

                var s = 0
                for t in tokens {
                    if title.hasPrefix(t) {
                        s += 2
                    } else if title.contains(t) {
                        s += 1
                    }
                }
                if let year = selectedYear, movie.year == year {
                    s += 1
                }
                return s
            }

            movies.sort { lhs, rhs in
                let ls = score(for: lhs)
                let rs = score(for: rhs)
                if ls != rs { return ls > rs }

                if lhs.rating != rhs.rating { return lhs.rating > rhs.rating }

                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }

            results = movies
            print("[SearchVM] search done, results: \(movies.count)")
        } catch {
            self.error = error.localizedDescription
            print("[SearchVM] search error:", error)
        }
        isLoading = false
    }
}
