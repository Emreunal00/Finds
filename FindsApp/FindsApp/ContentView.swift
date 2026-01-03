import SwiftUI
import Combine
import FirebaseFirestore

private final class PosterRatingsCache: ObservableObject {
    static let shared = PosterRatingsCache()
    @Published private(set) var averages: [String: Double] = [:] // key: "type:id"

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

    private var welcomeTitle: String {
        let nickname: String = {
            if let name = authVM.user?.displayName, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
            Group {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // İçerik başlığı (large gibi görünür, ama navbara bağlı değil)
                        HStack {
                            Text(welcomeTitle)
                                .font(.largeTitle).bold()
                            Spacer()
                        }

                        Group {
                            if homeVM.isLoading && homeVM.trending.isEmpty && homeVM.suggestions.isEmpty && homeVM.trendingShows.isEmpty && homeVM.suggestedShows.isEmpty {
                                CustomLoadingView(message: "Loading…")
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else if let err = homeVM.error,
                                      homeVM.trending.isEmpty && homeVM.suggestions.isEmpty && homeVM.trendingShows.isEmpty && homeVM.suggestedShows.isEmpty {
                                VStack(spacing: 12) {
                                    Text("Failed to load")
                                        .font(.headline)
                                    Text(err)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                    Button("Retry") {
                                        Task { await homeVM.load(userID: authVM.user?.id) }
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
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 24)
                }
            }
            // Navigation bar’ı bu ekranda gizle: mini başlık görünmez
            .navigationBarHidden(true)
            .task {
                if homeVM.trending.isEmpty && homeVM.suggestions.isEmpty && homeVM.trendingShows.isEmpty && homeVM.suggestedShows.isEmpty {
                    await homeVM.load(userID: authVM.user?.id)
                }
                // Check onboarding status once per appearance
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
                        // If fetch fails, default to not showing onboarding to avoid blocking
                        print("[Onboarding] status fetch failed:", error.localizedDescription)
                    }
                }
            }
            .refreshable {
                await homeVM.load(userID: authVM.user?.id)
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                Hello()
                    .environmentObject(authVM)
                    .onDisappear {
                        // When Hello completes, ensure we don't show it again in this session
                        showOnboarding = false
                    }
            }
        }
    }
}

// MARK: - Section Header

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
                        MovieDetailView(movie: movie)
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
            placeholder
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
}

#Preview {
    ContentView()
        .environmentObject(AuthViewModel())
}
