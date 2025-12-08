// HomeViewModel.swift
import Foundation
import Combine

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var trending: [Movie] = []
    @Published var suggestions: [Movie] = []
    @Published var trendingShows: [Movie] = []
    @Published var suggestedShows: [Movie] = []
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

            var recMoviesTask: Task<[Movie], Error>? = nil
            var recShowsTask: Task<[Movie], Error>? = nil
            if let uid = userID, !uid.isEmpty {
                recMoviesTask = Task { try await recommendations.fetchRecommendedMovies(userID: uid) }
                recShowsTask = Task { try await recommendations.fetchRecommendedShows(userID: uid) }
            }

            let (tr, trTV) = try await (t, tvT)
            let recMovies = try await recMoviesTask?.value ?? []
            let recShows = try await recShowsTask?.value ?? []

            trending = tr
            trendingShows = trTV
            suggestions = recMovies
            suggestedShows = recShows
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
