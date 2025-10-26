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

    init(service: MovieServicing = MovieService()) {
        self.service = service
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        do {
            async let t = service.getTrending(page: 1)
            async let s = service.getSuggestions(page: 1)
            async let tvT = service.getTrendingTV(page: 1)       // NEW
            async let tvS = service.getSuggestionsTV(page: 1)    // NEW
            let (tr, sg, trTV, sgTV) = try await (t, s, tvT, tvS)
            trending = tr
            suggestions = sg
            trendingShows = trTV
            suggestedShows = sgTV
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
