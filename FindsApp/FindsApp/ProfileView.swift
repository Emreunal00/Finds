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
    
    @State private var pendingDeletionMovie: Movie? = nil
    @State private var pendingDeletionCustomList: ProfileCustomUserList? = nil

    @State private var showingNewListPrompt = false
    @State private var newListName: String = ""

    private let service: MovieServicing = MovieService()

    enum ListTab: String, CaseIterable, Identifiable {
        case favorites = "Favorites"
        case watchlist = "Watchlist"
        case watched = "Watched"
        case custom = "My Lists"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .favorites: return "heart.fill"
            case .watchlist: return "bookmark.fill"
            case .watched: return "checkmark.circle.fill"
            case .custom: return "list.bullet"
            }
        }
        var tint: Color {
            switch self {
            case .favorites: return .pink
            case .watchlist: return .blue
            case .watched: return .green
            case .custom: return .purple
            }
        }
        var emptyTitle: String {
            switch self {
            case .favorites: return "No favorites"
            case .watchlist: return "Watchlist is empty"
            case .watched: return "No watched items"
            case .custom: return "No custom lists"
            }
        }
        var emptySubtitle: String {
            switch self {
            case .favorites: return "Use the heart icon to add items to your favorites."
            case .watchlist: return "Use the bookmark icon to save items to your watchlist."
            case .watched: return "Use the checkmark to mark items as watched."
            case .custom: return "Create and manage your own collections."
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
                        showingNewListPrompt = false
                        newListName = ""
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
            .confirmationDialog("Remove from \(selectedTab.rawValue)?", isPresented: .constant(pendingDeletionMovie != nil), presenting: pendingDeletionMovie) { movie in
                Button("Remove", role: .destructive) {
                    let id = movie.id
                    let type = movie.mediaType
                    Task { await removeFromCurrentList(movieID: id, mediaType: type) }
                    pendingDeletionMovie = nil
                }
                Button("Cancel", role: .cancel) { pendingDeletionMovie = nil }
            } message: { movie in
                Text("This will remove \(movie.title) from your \(selectedTab.rawValue).")
            }
            .confirmationDialog("Delete list?", isPresented: .constant(pendingDeletionCustomList != nil), presenting: pendingDeletionCustomList) { list in
                Button("Delete", role: .destructive) {
                    Task { await deleteCustomList(listID: list.id) }
                    pendingDeletionCustomList = nil
                }
                Button("Cancel", role: .cancel) { pendingDeletionCustomList = nil }
            } message: { list in
                Text("This will permanently delete the list \"\(list.name)\".")
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
            .onChange(of: navPath) { _ in
                showingNewListPrompt = false
                newListName = ""
            }
            .onDisappear {
                showingNewListPrompt = false
                newListName = ""
                stopCustomListsListener()
            }
            .navigationDestination(for: ListTab.self) { tab in
                switch tab {
                case .favorites:
                    FavoritesListView().environmentObject(authVM)
                case .watchlist:
                    WatchlistListView().environmentObject(authVM)
                case .watched:
                    WatchedListView().environmentObject(authVM)
                case .custom:
                    VStack { Text("Custom Lists") }
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
                        HStack {
                            Label("My Lists", systemImage: "list.bullet").foregroundStyle(.purple)
                            Spacer()
                            Text("\(userCustomLists.count)").foregroundStyle(.secondary)
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
            VStack(spacing: 12) { CustomLoadingView(message: "Loading…") }
                .frame(maxWidth: .infinity).padding()
        } else if let err = errorMessage {
            VStack(spacing: 8) {
                Text("Failed to load").font(.headline)
                Text(err).font(.footnote).foregroundStyle(.secondary)
                Button("Retry") { Task { await loadCurrentList(limitToFive: true) } }.buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity).padding(.horizontal).padding(.top, 8)
        } else if selectedTab != .custom {
            if movies.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: selectedTab.icon)
                        .font(.system(size: 28))
                        .foregroundStyle(selectedTab.tint)
                    Text(selectedTab.emptyTitle).font(.headline)
                    Text(selectedTab.emptySubtitle).font(.footnote).foregroundStyle(.secondary)
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
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    newListName = ""
                    showingNewListPrompt = true
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.purple)
                            Text("New List")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        .padding(12)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.top, 4)

                if showingNewListPrompt {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Create New List").font(.headline)
                        TextField("List name", text: $newListName)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Button("Cancel") { showingNewListPrompt = false }
                            Spacer()
                            Button("Create") {
                                let name = newListName.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !name.isEmpty else { return }
                                Task {
                                    await createNewCustomList(name: name)
                                    await MainActor.run {
                                        showingNewListPrompt = false
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(newListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .padding(.horizontal)
                }

                if userCustomLists.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: selectedTab.icon)
                            .font(.system(size: 28))
                            .foregroundStyle(selectedTab.tint)
                        Text(selectedTab.emptyTitle).font(.headline)
                        Text(selectedTab.emptySubtitle).font(.footnote).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)
                    .padding(.top, 8)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(userCustomLists) { list in
                            NavigationLink {
                                CustomListDetailView(list: list)
                                    .environmentObject(authVM)
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color(.secondarySystemBackground))
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(list.name)
                                                .font(.headline)
                                                .foregroundColor(.primary)
                                        }
                                        Spacer()
                                        Button(role: .destructive) {
                                            pendingDeletionCustomList = list
                                        } label: {
                                            Image(systemName: "minus.circle.fill").foregroundStyle(selectedTab.tint)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Delete list")
                                    }
                                    .padding(12)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
            }
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
                        pendingDeletionMovie = movie
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
                    ZStack { Color(.tertiarySystemFill); CustomLoadingView() }
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

    // MARK: - Create Custom List
    private func createNewCustomList(name: String) async {
        guard let uid = authVM.user?.id else { return }
        let db = Firestore.firestore()
        let listsRef = db.collection("users").document(uid).collection("lists")
        let newDoc = listsRef.document()
        let payload: [String: Any] = [
            "name": name,
            "createdAt": FieldValue.serverTimestamp()
        ]
        do {
            try await newDoc.setData(payload)
        } catch {
            await MainActor.run { self.errorMessage = "Couldn't create list. Please try again." }
        }
    }

    private func deleteCustomList(listID: String) async {
        guard let uid = authVM.user?.id else { return }
        let db = Firestore.firestore()
        let docRef = db.collection("users").document(uid).collection("lists").document(listID)
        do {
            try await docRef.delete()
        } catch {
            await MainActor.run { self.errorMessage = "Couldn't delete list. Please try again." }
        }
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
        case .custom:
            movies = []
            return
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
        case .custom:
            return false
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
        case .custom:
            break
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
                            .overlay { CustomLoadingView() }
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

