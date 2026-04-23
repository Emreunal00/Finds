// HomeViewModel.swift
import Foundation
import Combine

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var trending: [Movie] = []
    @Published var suggestions: [Movie] = []
    @Published var trendingShows: [Movie] = []
    @Published var suggestedShows: [Movie] = []
    @Published var trendingBooks: [Movie] = []
    @Published var suggestedBooks: [Movie] = []
    @Published var isLoading = false
    @Published var error: String?

    private let service: MovieServicing
    private let recommendations = RecommendationsService()

    init(service: MovieServicing = MovieService()) {
        self.service = service
    }

    func load(userID: String?) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        do {
            async let t = service.getTrending(page: 1)
            async let tvT = service.getTrendingTV(page: 1)
            async let booksT = BookCatalog.trendingBooks(page: 1)

            var recMoviesTask: Task<[Movie], Error>? = nil
            var recShowsTask: Task<[Movie], Error>? = nil
            var recBooksTask: Task<[Movie], Never>? = nil
            if let uid = userID, !uid.isEmpty {
                recMoviesTask = Task { try await recommendations.fetchRecommendedMovies(userID: uid) }
                recShowsTask = Task { try await recommendations.fetchRecommendedShows(userID: uid) }
            }
            recBooksTask = Task { await BookCatalog.recommendedBooks(for: userID, page: 1, pageSize: 30) }

            let (tr, trTV, trBooks) = try await (t, tvT, booksT)
            let recMovies = try await recMoviesTask?.value ?? []
            let recShows = try await recShowsTask?.value ?? []
            let recBooks = await recBooksTask?.value ?? []

            trending = tr
            trendingShows = trTV
            trendingBooks = trBooks
            suggestions = recMovies
            suggestedShows = recShows
            suggestedBooks = recBooks
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
