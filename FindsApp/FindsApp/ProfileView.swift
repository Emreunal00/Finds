import Combine
import Observation
import SwiftUI
import FirebaseFirestore

struct ProfileCustomUserList: Identifiable, Equatable {
    let id: String
    let name: String
}

private final class ProfileRatingsCache: ObservableObject {
    static let shared = ProfileRatingsCache()
    @Published private(set) var averages: [String: Double] = [:] // key: "type:id"
    private var ongoing: Set<String> = []

    func key(for movie: Movie) -> String { "\((movie.mediaType ?? "movie").lowercased()):\(movie.id)" }
    func average(for movie: Movie) -> Double? { averages[key(for: movie)] }

    func loadIfNeeded(for movie: Movie) {
        let k = key(for: movie)
        if averages[k] != nil || ongoing.contains(k) { return }
        ongoing.insert(k)
        Task { [weak self] in
            let repo = RatingsRepository()
            let type = (movie.mediaType ?? "movie").lowercased()
            do {
                if let agg = try await repo.fetchAggregate(movieID: movie.id, type: type) {
                    await MainActor.run { self?.averages[k] = agg.average; self?.ongoing.remove(k) }
                } else {
                    await MainActor.run { self?.averages[k] = 0; self?.ongoing.remove(k) }
                }
            } catch {
                await MainActor.run { self?.averages[k] = 0; self?.ongoing.remove(k) }
            }
        }
    }
}

struct ProfileView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var selectedTab: ListTab = .favorites
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var movies: [Movie] = []
    @StateObject private var ratingsCache = ProfileRatingsCache.shared
    @State private var navPath = NavigationPath()
    @State private var showingEditProfile = false
    @State private var userCustomLists: [ProfileCustomUserList] = []
    @State private var listsListener: ListenerRegistration? = nil
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
                        Task { await loadCurrentList(limitToFive: true) }
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
            .sheet(isPresented: $showingEditProfile) {
                EditProfileView()
                    .environmentObject(authVM)
            }
            .onAppear {
                Task { await loadCurrentList(limitToFive: true) }
                if let uid = authVM.user?.id { startCustomListsListener(uid: uid) }
            }
            .onChange(of: authVM.listsVersion) { _ in Task { await loadCurrentList(limitToFive: true) } }
            .onDisappear { stopCustomListsListener() }
            .navigationDestination(for: ListTab.self) { tab in
                switch tab {
                case .favorites:
                    FavoritesListView().environmentObject(authVM)
                case .watchlist:
                    WatchlistListView().environmentObject(authVM)
                case .watched:
                    WatchedListView().environmentObject(authVM)
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            Group {
                HStack(spacing: 12) {
                    profileAvatar
                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayName).font(.headline)
                        Text(email).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    // OK butonu: EditProfileView'i açar
                    Button {
                        showingEditProfile = true
                    } label: {
                        Image(systemName: "chevron.right.circle.fill")
                            .imageScale(.large)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(6)
                            .background(
                                Circle()
                                    .fill(Color(.secondarySystemBackground))
                            )
                            .accessibilityLabel("Edit Profile")
                    }
                    .buttonStyle(.plain)
                    .disabled(authVM.user == nil)
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
                            Text("\(u.favoritesEntries.count)").foregroundStyle(.secondary)
                        }
                        HStack {
                            Label("Watchlist", systemImage: "bookmark.fill").foregroundStyle(.blue)
                            Spacer()
                            Text("\(u.watchlistEntries.count)").foregroundStyle(.secondary)
                        }
                        HStack {
                            Label("Watched", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            Spacer()
                            Text("\(u.watchedEntries.count)").foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(.horizontal)

                Group {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Custom Lists")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if userCustomLists.isEmpty {
                            Text("No custom lists yet.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(userCustomLists) { list in
                                    NavigationLink {
                                        CustomListDetailView(list: list)
                                            .environmentObject(authVM)
                                    } label: {
                                        HStack {
                                            Text(list.name)
                                                .font(.body)
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .imageScale(.small)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                            }
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
                Button("Retry") { Task { await loadCurrentList(limitToFive: true) } }.buttonStyle(.borderedProminent)
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
                        .onAppear { ratingsCache.loadIfNeeded(for: movie) }
                    Divider()
                }

                if showAllButton {
                    Button {
                        navPath.append(selectedTab)
                    } label: {
                        HStack {
                            Spacer()
                            Text("All")
                                .font(.subheadline.weight(.semibold))
                            Image(systemName: "chevron.right")
                                .imageScale(.small)
                            Spacer()
                        }
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .tint(selectedTab.tint)
                    .padding(.vertical, 8)
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
                    if let avg = ratingsCache.average(for: movie) {
                        Text(String(format: "%.1f / 5", avg))
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

    // MARK: - Typed entries helpers

    private func currentFavoriteEntries() -> [WatchedEntry] {
        guard let u = authVM.user else { return [] }
        return u.favoritesEntries
    }

    private func currentWatchlistEntries() -> [WatchedEntry] {
        guard let u = authVM.user else { return [] }
        return u.watchlistEntries
    }

    private func currentWatchedEntries() -> [WatchedEntry] {
        guard let u = authVM.user else { return [] }
        return u.watchedEntries
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

    // MARK: - Firestore Custom Lists

    private func startCustomListsListener(uid: String) {
        let ref = Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("lists")
            .order(by: "createdAt", descending: false)
        listsListener = ref.addSnapshotListener { snapshot, error in
            if let error = error {
                print("[Profile Lists] listener error:", error.localizedDescription)
                return
            }
            guard let docs = snapshot?.documents else { return }
            let lists = docs.map { doc -> ProfileCustomUserList in
                let name = doc.data()["name"] as? String ?? "Untitled"
                return ProfileCustomUserList(id: doc.documentID, name: name)
            }
            self.userCustomLists = lists
        }
    }

    private func stopCustomListsListener() {
        listsListener?.remove()
        listsListener = nil
    }

    // MARK: - Data loading

    private func loadCurrentList(limitToFive: Bool) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        switch selectedTab {
        case .favorites:
            let entries = currentFavoriteEntries()
            guard !entries.isEmpty else { movies = []; return }
            let ordered = Array(entries.reversed())
            let limited = limitToFive ? Array(ordered.prefix(5)) : ordered
            do {
                let fetched: [Movie] = await withTaskGroup(of: (Int, Movie?).self) { group -> [Movie] in
                    for entry in limited {
                        group.addTask {
                            do {
                                if entry.type.lowercased() == "movie" {
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
                    while let next = await group.next() { items.append(next) }
                    let map = Dictionary(uniqueKeysWithValues: items)
                    let orderedMovies = limited.compactMap { map[$0.id] ?? nil }
                    return orderedMovies.compactMap { $0 }
                }
                movies = fetched
            }

        case .watchlist:
            let entries = currentWatchlistEntries()
            guard !entries.isEmpty else { movies = []; return }
            let ordered = Array(entries.reversed())
            let limited = limitToFive ? Array(ordered.prefix(5)) : ordered
            do {
                let fetched: [Movie] = await withTaskGroup(of: (Int, Movie?).self) { group -> [Movie] in
                    for entry in limited {
                        group.addTask {
                            do {
                                if entry.type.lowercased() == "movie" {
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
                    while let next = await group.next() { items.append(next) }
                    let map = Dictionary(uniqueKeysWithValues: items)
                    let orderedMovies = limited.compactMap { map[$0.id] ?? nil }
                    return orderedMovies.compactMap { $0 }
                }
                movies = fetched
            }

        case .watched:
            let entries = currentWatchedEntries()
            guard !entries.isEmpty else { movies = []; return }
            let ordered = Array(entries.reversed())
            let limited = limitToFive ? Array(ordered.prefix(5)) : ordered
            do {
                let fetched: [Movie] = await withTaskGroup(of: (Int, Movie?).self) { group -> [Movie] in
                    for entry in limited {
                        group.addTask {
                            do {
                                if entry.type.lowercased() == "movie" {
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
                    while let next = await group.next() { items.append(next) }
                    let map = Dictionary(uniqueKeysWithValues: items)
                    let orderedMovies = limited.compactMap { map[$0.id] ?? nil }
                    return orderedMovies.compactMap { $0 }
                }
                movies = fetched
            }
        }
    }

    private var showAllButton: Bool {
        guard let u = authVM.user else { return false }
        switch selectedTab {
        case .favorites:
            return u.favoritesEntries.count > 5
        case .watchlist:
            return u.watchlistEntries.count > 5
        case .watched:
            return u.watchedEntries.count > 5
        }
    }

    private func removeFromCurrentList(movieID: Int, mediaType: String?) async {
        switch selectedTab {
        case .favorites:
            await authVM.toggleFavorite(movieID: movieID, mediaType: mediaType ?? "movie")
        case .watchlist:
            await authVM.toggleWatchlist(movieID: movieID, mediaType: mediaType ?? "movie")
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

    @ViewBuilder
    private var profileAvatar: some View {
        if let urlStr = authVM.user?.photoURL {
            if urlStr.hasPrefix("avatar://") {
                let id = String(urlStr.dropFirst("avatar://".count))
                Image(id)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())
            } else if let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        Circle().fill(Color(.tertiarySystemFill))
                            .frame(width: 56, height: 56)
                            .overlay { ProgressView() }
                    case .success(let img):
                        img.resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                    case .failure:
                        profilePlaceholder
                    @unknown default:
                        profilePlaceholder
                    }
                }
            } else {
                profilePlaceholder
            }
        } else {
            profilePlaceholder
        }
    }

    private var profilePlaceholder: some View {
        Circle()
            .fill(Color(.tertiarySystemFill))
            .frame(width: 56, height: 56)
            .overlay {
                Image(systemName: "person.fill")
                    .foregroundStyle(.secondary)
            }
    }
}

#Preview {
    ProfileView()
        .environmentObject(AuthViewModel())
}
