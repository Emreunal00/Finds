
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
    private var loadToken = 0

    init(service: MovieServicing = MovieService()) {
        self.service = service
    }

    func load(userID: String?, profile: Profile?) async {
        loadToken &+= 1
        let token = loadToken
        let profileID = profile?.id

        isLoading = true
        error = nil
        do {
            async let t = service.getTrending(page: 1)
            async let tvT = service.getTrendingTV(page: 1)
            async let booksT = BookCatalog.trendingBooks(page: 1)

            var recMoviesTask: Task<[Movie], Error>? = nil
            var recShowsTask: Task<[Movie], Error>? = nil
            var recBooksTask: Task<[Movie], Error>? = nil
            if let uid = userID, !uid.isEmpty, let profileID, !profileID.isEmpty {
                recMoviesTask = Task { try await recommendations.fetchRecommendedMovies(userID: uid, profileID: profileID) }
                recShowsTask = Task { try await recommendations.fetchRecommendedShows(userID: uid, profileID: profileID) }
                recBooksTask = Task { try await recommendations.fetchRecommendedBooks(userID: uid, profileID: profileID) }
            }

            let (tr, trTV, trBooks) = try await (t, tvT, booksT)
            let recMovies = try await recMoviesTask?.value ?? []
            let recShows = try await recShowsTask?.value ?? []
            let recBooks = try await recBooksTask?.value ?? []

            guard token == loadToken else { return }

            trending = tr
            trendingShows = trTV
            trendingBooks = trBooks
            suggestions = Self.visibleRecommendations(recMovies, for: profile)
            suggestedShows = Self.visibleRecommendations(recShows, for: profile)
            suggestedBooks = Self.visibleRecommendations(recBooks, for: profile)
            isLoading = false
        } catch {
            guard token == loadToken else { return }
            self.error = error.localizedDescription
            isLoading = false
        }
    }

    func reloadRecommendations(userID: String?, profile: Profile?) async {
        suggestions = []
        suggestedShows = []
        suggestedBooks = []
        await load(userID: userID, profile: profile)
    }

    private static func visibleRecommendations(_ movies: [Movie], for profile: Profile?) -> [Movie] {
        guard let profile else { return movies }
        return movies.filter { profile.shouldShowAsRecommendation($0) }
    }
}
