// HomeViewModel.swift
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var trending: [Movie] = []
    @Published var suggestions: [Movie] = []
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
            let (tr, sg) = try await (t, s)
            trending = tr
            suggestions = sg
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
