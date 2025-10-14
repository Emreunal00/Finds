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
        do {
            genres = try await service.fetchGenres()
        } catch {
            // genre çekilemese de arama çalışsın
        }
    }

    func search() async {
        let q = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            results = []
            return
        }
        isLoading = true
        error = nil
        do {
            // Multi Search
            var movies = try await service.searchMulti(query: q, page: 1)

            // Client-side filtreleme: yıl ve genre
            if let year = selectedYear {
                movies = movies.filter { $0.year == year }
            }
            if let gid = selectedGenreID {
                // Mevcut Movie.genres dizi içinde TMDb genre isimleri yok; ID stringlerini "#<id>" olarak tutuyoruz.
                // Bu nedenle ID ile filtreleme: "#<id>" stringi içeriyor mu?
                let token = "#\(gid)"
                movies = movies.filter { $0.genres.contains(token) }
            }

            results = movies
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
