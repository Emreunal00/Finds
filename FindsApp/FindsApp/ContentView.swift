import SwiftUI
import Combine
import FirebaseFirestore

private final class PosterRatingsCache: ObservableObject {
    static let shared = PosterRatingsCache()
    @Published private(set) var averages: [String: Double] = [:] 

    private var ongoingTasks: Set<String> = []

    func key(for movie: Movie) -> String { "\((movie.mediaType ?? "movie").lowercased()):\(movie.id)" }

    func average(for movie: Movie) -> Double? { averages[key(for: movie)] }

    func loadIfNeeded(for movie: Movie) {
        let k = key(for: movie)
        if averages[k] != nil || ongoingTasks.contains(k) { return }
        ongoingTasks.insert(k)
        Task { [weak self] in
            let repo = RatingsRepository()
            let type = (movie.mediaType ?? "movie").lowercased()
            do {
                if let agg = try await repo.fetchAggregate(movieID: movie.id, type: type) {
                    await MainActor.run {
                        self?.averages[k] = agg.average
                        self?.ongoingTasks.remove(k)
                    }
                } else {
                    await MainActor.run {
                        self?.averages[k] = 0
                        self?.ongoingTasks.remove(k)
                    }
                }
            } catch {
                await MainActor.run {
                    self?.averages[k] = 0
                    self?.ongoingTasks.remove(k)
                }
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @StateObject private var homeVM = HomeViewModel()
    @State private var showProfile = false

    @State private var showOnboarding = false
    @State private var onboardingChecked = false
    @State private var showMiniGame = false

    private var welcomeTitle: String {
        let nickname: String = {
            if let name = authVM.currentProfile?.displayName, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return name
            }
            if let email = authVM.user?.email, let at = email.firstIndex(of: "@") {
                let handle = String(email[..<at])
                if !handle.isEmpty { return handle }
            }
            return "User"
        }()
        return "Welcome, \(nickname) 👋"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Group {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            
                            HStack {
                                Text(welcomeTitle)
                                    .font(.largeTitle).bold()
                                Spacer()
                            }

                            Group {
                                if homeVM.isLoading && homeVM.trending.isEmpty && homeVM.suggestions.isEmpty && homeVM.trendingShows.isEmpty && homeVM.suggestedShows.isEmpty && homeVM.trendingBooks.isEmpty && homeVM.suggestedBooks.isEmpty {
                                    CustomLoadingView(message: "Loading…")
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                } else if let err = homeVM.error,
                                          homeVM.trending.isEmpty && homeVM.suggestions.isEmpty && homeVM.trendingShows.isEmpty && homeVM.suggestedShows.isEmpty && homeVM.trendingBooks.isEmpty && homeVM.suggestedBooks.isEmpty {
                                    VStack(spacing: 12) {
                                        Text("Failed to load")
                                            .font(.headline)
                                        Text(err)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                        Button("Retry") {
                                            Task { await homeVM.load(userID: authVM.user?.id, profileID: authVM.currentProfile?.id) }
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .padding()
                                } else {
                                    VStack(alignment: .leading, spacing: 24) {
                                        if !homeVM.trending.isEmpty {
                                            NavigationLink {
                                                MoreListView(kind: .trendingMovies)
                                            } label: {
                                                SectionHeader(title: "Trending movies", showsChevron: true)
                                            }
                                            .buttonStyle(.plain)
                                            PosterHScroll(movies: homeVM.trending)
                                        }

                                        if !homeVM.suggestions.isEmpty {
                                            NavigationLink {
                                                MoreListView(kind: .suggestedMovies)
                                            } label: {
                                                SectionHeader(title: "Top picks for you", showsChevron: true)
                                            }
                                            .buttonStyle(.plain)
                                            PosterHScroll(movies: homeVM.suggestions)
                                        }

                                        if !homeVM.trendingShows.isEmpty {
                                            NavigationLink {
                                                MoreListView(kind: .trendingTV)
                                            } label: {
                                                SectionHeader(title: "Trending shows", showsChevron: true)
                                            }
                                            .buttonStyle(.plain)
                                            PosterHScroll(movies: homeVM.trendingShows)
                                        }

                                        if !homeVM.suggestedShows.isEmpty {
                                            NavigationLink {
                                                MoreListView(kind: .suggestedTV)
                                            } label: {
                                                SectionHeader(title: "Suggested Shows", showsChevron: true)
                                            }
                                            .buttonStyle(.plain)
                                            PosterHScroll(movies: homeVM.suggestedShows)
                                        }

                                        if !homeVM.trendingBooks.isEmpty {
                                            NavigationLink {
                                                MoreListView(kind: .trendingBooks)
                                            } label: {
                                                SectionHeader(title: "Popular books", showsChevron: true)
                                            }
                                            .buttonStyle(.plain)
                                            BookHScroll(books: homeVM.trendingBooks)
                                        }

                                        if !homeVM.suggestedBooks.isEmpty {
                                            NavigationLink {
                                                MoreListView(kind: .suggestedBooks)
                                            } label: {
                                                SectionHeader(title: "Recommended books", showsChevron: true)
                                            }
                                            .buttonStyle(.plain)
                                            BookHScroll(books: homeVM.suggestedBooks)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 24)
                    }
                }

                HomeMiniGameLauncher(isPresented: $showMiniGame)
            }
            
            .navigationBarHidden(true)
            .task {
                if homeVM.trending.isEmpty && homeVM.suggestions.isEmpty && homeVM.trendingShows.isEmpty && homeVM.suggestedShows.isEmpty && homeVM.trendingBooks.isEmpty && homeVM.suggestedBooks.isEmpty {
                    await homeVM.load(userID: authVM.user?.id, profileID: authVM.currentProfile?.id)
                }
                
                guard !onboardingChecked else { return }
                onboardingChecked = true
                if let uid = authVM.user?.id {
                    do {
                        let doc = try await Firestore.firestore().collection("users").document(uid).getDocument()
                        let completed = (doc.data()?["onboardingCompleted"] as? Bool) ?? false
                        if !completed {
                            await MainActor.run { showOnboarding = true }
                        }
                    } catch {
                        
                        print("[Onboarding] status fetch failed:", error.localizedDescription)
                    }
                }
            }
            .refreshable {
                await homeVM.load(userID: authVM.user?.id, profileID: authVM.currentProfile?.id)
            }
            .onChange(of: authVM.currentProfile?.id) { _, profileID in
                Task {
                    await homeVM.reloadRecommendations(userID: authVM.user?.id, profileID: profileID)
                }
            }
            .onChange(of: authVM.listsVersion) { _, _ in
                Task {
                    await homeVM.reloadRecommendations(userID: authVM.user?.id, profileID: authVM.currentProfile?.id)
                }
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                Hello()
                    .environmentObject(authVM)
                    .onDisappear {
                        
                        showOnboarding = false
                    }
            }
        }
    }
}



private struct SectionHeader: View {
    let title: String
    var showsChevron: Bool = false
    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.title3).bold()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }
}

private struct PosterHScroll: View {
    let movies: [Movie]

    @StateObject private var ratingsCache = PosterRatingsCache.shared

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(movies) { movie in
                    NavigationLink {
                        MediaDetailDestination(item: movie)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            poster(for: movie)
                                .frame(width: 120, height: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.black.opacity(0.06))
                                }
                            Text(movie.title)
                                .font(.footnote)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .frame(width: 120, alignment: .leading)
                            HStack(spacing: 6) {
                                if movie.year > 0 {
                                    Text(String(movie.year))
                                }
                                if let avg = ratingsCache.average(for: movie) {
                                    Text(String(format: "%.1f / 5", avg))
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .onAppear { ratingsCache.loadIfNeeded(for: movie) }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func poster(for movie: Movie) -> some View {
        if let url = movie.posterURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ZStack {
                        Color(.tertiarySystemFill)
                        CustomLoadingView()
                    }
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
        } else if !movie.posterName.isEmpty {
            Image(movie.posterName)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Color(.tertiarySystemFill)
                placeholderSymbol(for: movie)
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            Color(.tertiarySystemFill)
            Image(systemName: "film")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
        }
    }

    private func placeholderSymbol(for movie: Movie) -> some View {
        Image(systemName: BookCatalog.symbolName(for: movie))
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
    }
}

private struct BookHScroll: View {
    let books: [Movie]

    @StateObject private var ratingsCache = PosterRatingsCache.shared

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(books) { book in
                    NavigationLink {
                        MediaDetailDestination(item: book)
                    } label: {
                        BookHomeCard(book: book, average: ratingsCache.average(for: book))
                    }
                    .buttonStyle(.plain)
                    .onAppear { ratingsCache.loadIfNeeded(for: book) }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct BookHomeCard: View {
    let book: Movie
    let average: Double?

    private var authorText: String {
        let authors = book.directors ?? []
        if authors.isEmpty { return "Unknown author" }
        return authors.prefix(2).joined(separator: ", ")
    }

    private var genreText: String {
        book.genres.first ?? "Book"
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(cardGradient)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: BookCatalog.symbolName(for: book))
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.12))
                        .padding(.top, 14)
                        .padding(.trailing, 16)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                }

            HStack(alignment: .bottom, spacing: 12) {
                cover
                    .frame(width: 58, height: 86)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    }
                    .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 5)

                VStack(alignment: .leading, spacing: 8) {
                    Text(genreText.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .lineLimit(1)

                    Text(book.title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)

                    Text(authorText)
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.78))
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        if book.year > 0 {
                            Label(String(book.year), systemImage: "calendar")
                        }

                        if let average {
                            Label(String(format: "%.1f", average), systemImage: "star.fill")
                        }
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.82))
                }
                .frame(width: 136, alignment: .leading)
            }
            .padding(14)
        }
        .frame(width: 230, height: 150)
    }

    @ViewBuilder
    private var cover: some View {
        if let url = book.posterURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    coverPlaceholder
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    coverPlaceholder
                @unknown default:
                    coverPlaceholder
                }
            }
        } else if !book.posterName.isEmpty {
            Image(book.posterName)
                .resizable()
                .scaledToFill()
        } else {
            coverPlaceholder
        }
    }

    private var coverPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.26),
                    Color.white.opacity(0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: BookCatalog.symbolName(for: book))
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.75))
        }
    }

    private var cardGradient: LinearGradient {
        let colors = palette(for: book)
        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func palette(for book: Movie) -> [Color] {
        let palettes: [[Color]] = [
            [Color(red: 0.10, green: 0.34, blue: 0.25), Color(red: 0.16, green: 0.66, blue: 0.44)],
            [Color(red: 0.18, green: 0.28, blue: 0.42), Color(red: 0.25, green: 0.52, blue: 0.62)],
            [Color(red: 0.32, green: 0.22, blue: 0.16), Color(red: 0.66, green: 0.43, blue: 0.24)],
            [Color(red: 0.26, green: 0.22, blue: 0.38), Color(red: 0.48, green: 0.42, blue: 0.66)]
        ]
        let index = abs(book.title.unicodeScalars.reduce(0) { $0 + Int($1.value) }) % palettes.count
        return palettes[index]
    }
}
#Preview {
    ContentView()
        .environmentObject(AuthViewModel())
}
