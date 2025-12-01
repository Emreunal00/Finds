import SwiftUI

protocol AuthWatchChecking {
    func isWatched(movieID: Int, type: String) -> Bool
}
protocol AuthWatchlistChecking {
    func isInWatchlist(movieID: Int, type: String) -> Bool
}
protocol AuthFavoriteChecking {
    func isFavorite(movieID: Int, type: String) -> Bool
}
protocol AuthSetsProviding {
    var watchedIDs: Set<Int> { get }
    var watchlistIDs: Set<Int> { get }
    var favoriteIDs: Set<Int> { get }
}

struct PickerView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var movies: [Movie] = []
    @State private var currentIndex: Int = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isLoading: Bool = true
    @State private var error: String? = nil

    @State private var localWatched: Set<String> = []
    @State private var localWatchlist: Set<String> = []
    @State private var localFavorites: Set<String> = []

    // Helpers to reflect dynamic states (fallbacks if VM doesn't expose sets)
    private func isWatched(_ movie: Movie) -> Bool {
        let type = (movie.mediaType ?? "movie").lowercased()
        let key = "\(type):\(movie.id)"
        if localWatched.contains(key) { return true }
        if let checker = authVM as? (any AuthWatchChecking) {
            return checker.isWatched(movieID: movie.id, type: type)
        }
        if let setProvider = authVM as? (any AuthSetsProviding) {
            return setProvider.watchedIDs.contains(movie.id)
        }
        return false
    }
    private func isInWatchlist(_ movie: Movie) -> Bool {
        let type = (movie.mediaType ?? "movie").lowercased()
        let key = "\(type):\(movie.id)"
        if localWatchlist.contains(key) { return true }
        if let checker = authVM as? (any AuthWatchlistChecking) {
            return checker.isInWatchlist(movieID: movie.id, type: type)
        }
        if let setProvider = authVM as? (any AuthSetsProviding) {
            return setProvider.watchlistIDs.contains(movie.id)
        }
        return false
    }
    private func isFavorite(_ movie: Movie) -> Bool {
        let type = (movie.mediaType ?? "movie").lowercased()
        let key = "\(type):\(movie.id)"
        if localFavorites.contains(key) { return true }
        if let checker = authVM as? (any AuthFavoriteChecking) {
            return checker.isFavorite(movieID: movie.id, type: type)
        }
        if let setProvider = authVM as? (any AuthSetsProviding) {
            return setProvider.favoriteIDs.contains(movie.id)
        }
        return false
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer(minLength: 0)
                if isLoading {
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                        Text("Failed to load").font(.headline)
                        Text(error).font(.footnote).foregroundStyle(.secondary)
                        Button("Try Again") {
                            loadMovies()
                        }.buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let movie = movies[safe: currentIndex] {
                    // Movie poster with swipe gesture
                    ZStack {
                        AsyncImage(url: movie.posterURL) { phase in
                            switch phase {
                            case .empty: ProgressView()
                            case .success(let image): image.resizable().scaledToFill()
                            case .failure:
                                Image(systemName: "film")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 56, height: 68)
                                    .foregroundStyle(.secondary)
                            @unknown default: EmptyView()
                            }
                        }
                        .frame(width: 320, height: 500)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                        // Glow overlay based on drag direction
                        // REMOVED as per instructions
                    }
                    // Interactive effects based on drag
                    .offset(x: dragOffset)
                    .rotationEffect(.degrees(Double(dragOffset) / 20))
                    .scaleEffect(1 - min(abs(dragOffset) / 1200, 0.08))
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                dragOffset = value.translation.width
                            }
                            .onEnded { _ in
                                let threshold: CGFloat = 90
                                if dragOffset < -threshold {
                                    // Swiped left (dislike)
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                        if !movies.isEmpty {
                                            _ = movies.remove(at: currentIndex)
                                            currentIndex = min(currentIndex, max(movies.count - 1, 0))
                                        }
                                    }
                                } else if dragOffset > threshold {
                                    // Swiped right (like)
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                        if !movies.isEmpty {
                                            _ = movies.remove(at: currentIndex)
                                            currentIndex = min(currentIndex, max(movies.count - 1, 0))
                                        }
                                    }
                                }
                                withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                                    dragOffset = 0
                                }
                            }
                    )
                    .animation(.interactiveSpring(), value: dragOffset)
                    .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
                    // Movie title wrapped with NavigationLink
                    NavigationLink {
                        MovieDetailView(movie: movie)
                    } label: {
                        Text(movie.title)
                            .font(.title2).bold()
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                            .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)
                    // Action buttons
                    HStack(spacing: 14) {
                        Button {
                            let type = (movie.mediaType ?? "movie").lowercased()
                            let key = "\(type):\(movie.id)"
                            if localWatched.contains(key) { localWatched.remove(key) } else { localWatched.insert(key) }
                            Task { await authVM.toggleWatched(movieID: movie.id, type: type) }
                        } label: {
                            Label(isWatched(movie) ? "Watched" : "Watched", systemImage: isWatched(movie) ? "checkmark.circle.fill" : "checkmark.circle")
                                .labelStyle(.titleAndIcon)
                                .frame(minWidth: 0, maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(isWatched(movie) ? .green : .secondary)
                        .disabled(authVM.user == nil)

                        Button {
                            let type = (movie.mediaType ?? "movie").lowercased()
                            let key = "\(type):\(movie.id)"
                            if localWatchlist.contains(key) { localWatchlist.remove(key) } else { localWatchlist.insert(key) }
                            Task { await authVM.toggleWatchlist(movieID: movie.id, mediaType: type) }
                        } label: {
                            Label(isInWatchlist(movie) ? "Watchlist" : "Watchlist", systemImage: isInWatchlist(movie) ? "bookmark.fill" : "bookmark")
                                .labelStyle(.titleAndIcon)
                                .frame(minWidth: 0, maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(isInWatchlist(movie) ? .blue : .secondary)
                        .disabled(authVM.user == nil)

                        Button {
                            let type = (movie.mediaType ?? "movie").lowercased()
                            let key = "\(type):\(movie.id)"
                            if localFavorites.contains(key) { localFavorites.remove(key) } else { localFavorites.insert(key) }
                            Task { await authVM.toggleFavorite(movieID: movie.id, mediaType: type) }
                        } label: {
                            Label(isFavorite(movie) ? "Favorite" : "Favorite", systemImage: isFavorite(movie) ? "heart.fill" : "heart")
                                .labelStyle(.titleAndIcon)
                                .frame(minWidth: 0, maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(isFavorite(movie) ? .pink : .secondary)
                        .disabled(authVM.user == nil)
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 8)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "film")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No movies available.")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Button("Reload") {
                            loadMovies()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Spacer(minLength: 0)
            }
            .background(
                ZStack {
                    // Left red glow
                    LinearGradient(
                        colors: [Color.red.opacity(0.45), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .opacity(max(0, Double(min(abs(dragOffset) / 120, 1.0))) * (dragOffset < 0 ? 1 : 0))
                    .ignoresSafeArea()

                    // Right green glow
                    LinearGradient(
                        colors: [Color.clear, Color.green.opacity(0.45)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .opacity(max(0, Double(min(abs(dragOffset) / 120, 1.0))) * (dragOffset > 0 ? 1 : 0))
                    .ignoresSafeArea()
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Picker")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            if movies.isEmpty { loadMovies() }
        }
    }
    
    private func loadMovies() {
        isLoading = true
        error = nil
        Task {
            do {
                async let moviesPage1 = MovieService().getTrending(page: 1)
                async let moviesPage2 = MovieService().getTrending(page: 2)
                // Assuming there is a TV trending endpoint
                async let tvPage1 = MovieService().getTrendingTV(page: 1)
                async let tvPage2 = MovieService().getTrendingTV(page: 2)

                var combined: [Movie] = []
                combined += try await moviesPage1
                combined += try await moviesPage2
                combined += try await tvPage1
                combined += try await tvPage2

                combined.shuffle()

                await MainActor.run {
                    self.movies = combined
                    self.currentIndex = 0
                    self.isLoading = false
                    if let profile = authVM.user {
                        self.localWatched = Set(profile.watchedEntries.map { "\($0.type.lowercased()):\($0.id)" })
                        self.localWatchlist = Set(profile.watchlistEntries.map { "\($0.type.lowercased()):\($0.id)" })
                        self.localFavorites = Set(profile.favoritesEntries.map { "\($0.type.lowercased()):\($0.id)" })
                    } else {
                        self.localWatched = []
                        self.localWatchlist = []
                        self.localFavorites = []
                    }
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
}

// Safe array subscript for preview and logic
private extension Array {
    subscript(safe index: Int) -> Element? {
        (startIndex <= index && index < endIndex) ? self[index] : nil
    }
}

#Preview {
    PickerView()
        .environmentObject(AuthViewModel())
}
