import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var selectedTab: ListTab = .favorites
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var movies: [Movie] = []
    @State private var navPath = NavigationPath()
    private let service: MovieServicing = MovieService()

    enum ListTab: String, CaseIterable, Identifiable {
        case favorites = "Favorites"
        case watchlist = "Watchlist"
        case watched = "Watched"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .favorites: return "heart.fill"
            case .watchlist: return "bookmark.fill"
            case .watched: return "checkmark.circle.fill"
            }
        }
        var tint: Color {
            switch self {
            case .favorites: return .pink
            case .watchlist: return .blue
            case .watched: return .green
            }
        }
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    headerSection
                    Picker("", selection: $selectedTab) {
                        ForEach(ListTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 4)
                    .onChange(of: selectedTab) { _ in
                        Task { await loadCurrentList() }
                    }

                    contentSection

                    Group {
                        Button(role: .destructive) {
                            authVM.signOut()
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
                .padding(.bottom, 16)
            }
            .navigationTitle("Profile")
            .onAppear { Task { await loadCurrentList() } }
            .onChange(of: authVM.listsVersion) { _ in Task { await loadCurrentList() } }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            Group {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayName).font(.headline)
                        Text(email).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal)

            if let u = authVM.user {
                Group {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("My Lists")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack {
                            Label("Favorites", systemImage: "heart.fill").foregroundStyle(.pink)
                            Spacer()
                            Text("\(u.favoritesIDs.count)").foregroundStyle(.secondary)
                        }
                        HStack {
                            Label("Watchlist", systemImage: "bookmark.fill").foregroundStyle(.blue)
                            Spacer()
                            Text("\(u.watchlistIDs.count)").foregroundStyle(.secondary)
                        }
                        HStack {
                            Label("Watched", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            Spacer()
                            Text("\(u.watchedEntries.isEmpty ? u.watchedIDs.count : u.watchedEntries.count)").foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(.horizontal)
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var contentSection: some View {
        if isLoading {
            VStack(spacing: 12) { ProgressView("Loading…") }
                .frame(maxWidth: .infinity).padding()
        } else if let err = errorMessage {
            VStack(spacing: 8) {
                Text("Failed to load").font(.headline)
                Text(err).font(.footnote).foregroundStyle(.secondary)
                Button("Retry") { Task { await loadCurrentList() } }.buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity).padding(.horizontal).padding(.top, 8)
        } else if movies.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: selectedTab.icon)
                    .font(.system(size: 28))
                    .foregroundStyle(selectedTab.tint)
                Text(emptyTitle).font(.headline)
                Text(emptySubtitle).font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.horizontal).padding(.top, 8)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(movies) { movie in
                    NavigationLink { MovieDetailView(movie: movie) } label: { row(for: movie) }
                        .buttonStyle(.plain)
                    Divider()
                }
            }
            .padding(.horizontal).padding(.top, 8)
        }
    }

    private func row(for movie: Movie) -> some View {
        HStack(spacing: 12) {
            poster(for: movie)
                .frame(width: 70, height: 105)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(movie.title).font(.headline)
                    Spacer()
                    Button {
                        Task { await removeFromCurrentList(movieID: movie.id, mediaType: movie.mediaType) }
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(selectedTab.tint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Remove from list"))
                }
                HStack(spacing: 8) {
                    if movie.year > 0 { Text(String(movie.year)) }
                    if movie.rating > 0 {
                        let percent = Int(round(movie.rating * 20))
                        Text("\(percent)%").foregroundStyle(ScoreColor.color(for: percent))
                    }
                    if let runtime = movie.durationMinutes {
                        Label("\(runtime) min", systemImage: "clock").symbolRenderingMode(.hierarchical)
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                if !movie.summary.isEmpty {
                    Text(movie.summary).font(.caption).lineLimit(2).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func poster(for movie: Movie) -> some View {
        if let url = movie.posterURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ZStack { Color(.tertiarySystemFill); ProgressView() }
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
        } else if !movie.posterName.isEmpty {
            Image(movie.posterName).resizable().scaledToFill()
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Color(.tertiarySystemFill)
            Image(systemName: "film").font(.system(size: 20)).foregroundStyle(.secondary)
        }
    }

    // MARK: - Data loading

    private func currentIDs() -> [Int] {
        guard let u = authVM.user else { return [] }
        switch selectedTab {
        case .favorites: return u.favoritesIDs
        case .watchlist: return u.watchlistIDs
        case .watched: return [] // not used anymore
        }
    }

    private func currentWatchedEntries() -> [WatchedEntry] {
        guard let u = authVM.user else { return [] }
        if !u.watchedEntries.isEmpty {
            return u.watchedEntries
        } else {
            // fallback legacy: watchedIDs -> movie
            return u.watchedIDs.map { WatchedEntry(id: $0, type: "movie") }
        }
    }

    private func emptyTitleText(for tab: ListTab) -> String {
        switch tab {
        case .favorites: return "No favorites"
        case .watchlist: return "Watchlist is empty"
        case .watched: return "No watched items"
        }
    }

    private func emptySubtitleText(for tab: ListTab) -> String {
        switch tab {
        case .favorites: return "Use the heart icon to add items to your favorites."
        case .watchlist: return "Use the bookmark icon to save items to your watchlist."
        case .watched: return "Use the checkmark to mark items as watched."
        }
    }

    private var emptyTitle: String { emptyTitleText(for: selectedTab) }
    private var emptySubtitle: String { emptySubtitleText(for: selectedTab) }

    private func loadCurrentList() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        switch selectedTab {
        case .favorites, .watchlist:
            let ids = currentIDs()
            guard !ids.isEmpty else { movies = []; return }
            do {
                let fetched: [Movie] = try await withThrowingTaskGroup(of: (Int, Movie).self) { group in
                    for id in ids {
                        group.addTask {
                            let m = try await service.fetchMovieBasic(id: id)
                            return (id, m)
                        }
                    }
                    var items: [(Int, Movie)] = []
                    while let next = try await group.next() { items.append(next) }
                    let map = Dictionary(uniqueKeysWithValues: items)
                    return ids.compactMap { map[$0] }
                }
                movies = fetched
            } catch {
                errorMessage = error.localizedDescription
                movies = []
            }

        case .watched:
            let entries = currentWatchedEntries()
            guard !entries.isEmpty else { movies = []; return }
            do {
                let fetched: [Movie] = try await withThrowingTaskGroup(of: (Int, Movie?).self) { group in
                    for entry in entries {
                        group.addTask {
                            do {
                                if entry.type == "movie" {
                                    let m = try await service.fetchMovieBasic(id: entry.id)
                                    return (entry.id, m)
                                } else {
                                    let tv = try await service.fetchTVBasic(id: entry.id)
                                    return (entry.id, tv)
                                }
                            } catch {
                                return (entry.id, nil)
                            }
                        }
                    }
                    var items: [(Int, Movie?)] = []
                    while let next = try await group.next() { items.append(next) }
                    let map = Dictionary(uniqueKeysWithValues: items)
                    let ordered = entries.compactMap { map[$0.id] ?? nil }
                    return ordered.compactMap { $0 }
                }
                movies = fetched
            } catch {
                errorMessage = error.localizedDescription
                movies = []
            }
        }
    }

    private func removeFromCurrentList(movieID: Int, mediaType: String?) async {
        switch selectedTab {
        case .favorites:
            await authVM.toggleFavorite(movieID: movieID)
        case .watchlist:
            await authVM.toggleWatchlist(movieID: movieID)
        case .watched:
            let type = mediaType ?? "movie"
            await authVM.toggleWatched(movieID: movieID, type: type)
        }
        movies.removeAll { $0.id == movieID }
    }

    private var displayName: String {
        if let n = authVM.user?.displayName, !n.isEmpty { return n }
        return "User"
    }

    private var email: String {
        authVM.user?.email ?? "-"
    }
}

#Preview {
    ProfileView()
        .environmentObject(AuthViewModel())
}

