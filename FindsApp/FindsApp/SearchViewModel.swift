// SearchViewModel.swift
import Foundation

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
            let movies = try await service.searchMovies(query: q, year: selectedYear, genreID: selectedGenreID, page: 1)
            results = movies
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
