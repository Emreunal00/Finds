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
    private var cancellables = Set<AnyCancellable>()

    init(service: MovieServicing = MovieService()) {
        self.service = service

        // When keyword becomes empty, return to default search state automatically
        $keyword
            .removeDuplicates()
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .sink { [weak self] text in
                guard let self = self else { return }
                if text.isEmpty {
                    // Do not clear genres; only reset result-related state
                    self.results = []
                    self.error = nil
                    self.isLoading = false
                    // Keep selected filters? Usually default page has no filters.
                    self.selectedGenreID = nil
                    self.selectedYear = nil
                    print("[SearchVM] keyword cleared -> reset to default page")
                }
            }
            .store(in: &cancellables)
    }

    func reset() {
        print("[SearchVM] reset")
        keyword = ""
        selectedGenreID = nil
        selectedYear = nil
        results = []
        isLoading = false
        error = nil
        // genres listesi yüklendiyse kalsın
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
            async let screenResults = service.searchMulti(query: q, page: 1)
            async let bookResults = BookCatalog.searchBooks(query: q, maxResults: 12)

            var movies = try await screenResults
            let books = await bookResults
            movies.append(contentsOf: books)
            print("[SearchVM] combined search returned \(movies.count) items")

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
                movies = movies.filter { movie in
                    if movie.isBook {
                        return false
                    }
                    return movie.genres.contains(token)
                }
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

    // Janra bazlı gerçek içerik (discover movie+tv) — her tıklamada farklı sayfa
    func searchByGenre(genreID: Int) async {
        guard !isLoading else {
            print("[SearchVM] searchByGenre skipped: already loading")
            return
        }
        isLoading = true
        error = nil
        selectedGenreID = genreID

        // Basit çeşitlilik: 1...5 arası rastgele sayfa. İsterseniz 1...10 yapabilirsiniz.
        let randomPage = Int.random(in: 1...5)
        print("[SearchVM] discover start genreID=\(genreID) page=\(randomPage)")

        do {
            let movies = try await service.discoverMixed(genreID: genreID, page: randomPage)
            results = movies
            print("[SearchVM] discover done, results: \(movies.count)")
        } catch {
            self.error = error.localizedDescription
            print("[SearchVM] discover error:", error)
            results = []
        }
        isLoading = false
    }
}
