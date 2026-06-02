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
    @Published private(set) var averages: [String: Double] = [:] 
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
    @State private var showingSignOutConfirm = false

    @State private var showingNewListPrompt = false
    @State private var newListName: String = ""
    @State private var showingAddProfilePrompt = false
    @State private var newProfileName: String = ""

    private let service: MovieServicing = MovieService()

    enum ListTab: String, CaseIterable, Identifiable {
        case favorites = "Favorites"
        case watchlist = "Watchlist"
        case watched = "Watched"
        case wantToReadBooks = "Want to Read"
        case readBooks = "Read Books"
        case custom = "My Lists"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .favorites: return "heart.fill"
            case .watchlist: return "bookmark.fill"
            case .watched: return "checkmark.circle.fill"
            case .wantToReadBooks: return "book.pages.fill"
            case .readBooks: return "book.fill"
            case .custom: return "list.bullet"
            }
        }
        var tint: Color {
            switch self {
            case .favorites: return .pink
            case .watchlist: return .blue
            case .watched: return .green
            case .wantToReadBooks: return .blue
            case .readBooks: return .green
            case .custom: return .purple
            }
        }
        var emptyTitle: String {
            switch self {
            case .favorites: return "No favorites"
            case .watchlist: return "Watchlist is empty"
            case .watched: return "No watched items"
            case .wantToReadBooks: return "No books in want to read"
            case .readBooks: return "No read books"
            case .custom: return "No custom lists"
            }
        }
        var emptySubtitle: String {
            switch self {
            case .favorites: return "Use the heart icon to add items to your favorites."
            case .watchlist: return "Use the bookmark icon to save items to your watchlist."
            case .watched: return "Use the checkmark to mark items as watched."
            case .wantToReadBooks: return "Books you want to read will appear here."
            case .readBooks: return "Books you marked as read will appear here."
            case .custom: return "Create and manage your own collections."
            }
        }
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    headerSection
                    tabBarSection
                        .padding(.top, 4)
                        .onChange(of: selectedTab) { _ in
                        showingNewListPrompt = false
                        newListName = ""
                        Task { await loadCurrentList(limitToFive: true) }
                    }

                    contentSection
                }
                .padding(.bottom, 16)
            }
            .navigationTitle("Profile")
            .sheet(isPresented: $showingEditProfile) {
                EditProfileView()
                    .environmentObject(authVM)
            }
            .alert("Create Profile", isPresented: $showingAddProfilePrompt) {
                TextField("Profile name", text: $newProfileName)
                Button("Cancel", role: .cancel) {
                    newProfileName = ""
                }
                Button("Create") {
                    Task { await createProfile() }
                }
            } message: {
                Text("Add another profile under the same account.")
            }
            .onAppear {
                Task { await loadCurrentList(limitToFive: true) }
                if let uid = authVM.user?.id, let profileId = authVM.currentProfile?.id {
                    
                    startCustomListsListener(userId: uid, profileId: profileId)
                }
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
            
            .onChange(of: authVM.currentProfile) { newProfile in
                Task {
                    await loadCurrentList(limitToFive: true)
                    
                    stopCustomListsListener()
                    if let uid = authVM.user?.id, let profileId = newProfile?.id {
                        startCustomListsListener(userId: uid, profileId: profileId)
                    } else {
                        userCustomLists = []
                    }
                }
            }
            .navigationDestination(for: ListTab.self) { tab in
                switch tab {
                case .favorites:
                    FavoritesListView().environmentObject(authVM)
                case .watchlist:
                    WatchlistListView().environmentObject(authVM)
                case .watched:
                    WatchedListView().environmentObject(authVM)
                case .wantToReadBooks, .readBooks:
                    EmptyView()
                case .custom:
                    VStack { Text("Custom Lists") }
                }
            }
            .overlay {
                if let movie = pendingDeletionMovie {
                    ZStack {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                        VStack(spacing: 16) {
                            Text("Remove from \(selectedTab.rawValue)?")
                                .font(.headline)
                            Text("This will remove \(movie.title) from your \(selectedTab.rawValue).")
                                .multilineTextAlignment(.center)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            HStack {
                                Button("Cancel") {
                                    pendingDeletionMovie = nil
                                }
                                .buttonStyle(.bordered)
                                Spacer()
                                Button("Remove") {
                                    let id = movie.id
                                    let type = movie.mediaType
                                    Task {
                                        await removeFromCurrentList(movieID: id, mediaType: type)
                                    }
                                    pendingDeletionMovie = nil
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                            }
                        }
                        .padding(24)
                        .frame(maxWidth: 320)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(.systemBackground))
                        )
                        .padding(.horizontal, 40)
                    }
                }
            }
            .overlay {
                if let list = pendingDeletionCustomList {
                    ZStack {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                        VStack(spacing: 16) {
                            Text("Delete list?")
                                .font(.headline)
                            Text("This will permanently delete the list \"\(list.name)\".")
                                .multilineTextAlignment(.center)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            HStack {
                                Button("Cancel") {
                                    pendingDeletionCustomList = nil
                                }
                                .buttonStyle(.bordered)
                                Spacer()
                                Button("Delete") {
                                    Task {
                                        await deleteCustomList(listID: list.id)
                                    }
                                    pendingDeletionCustomList = nil
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                            }
                        }
                        .padding(24)
                        .frame(maxWidth: 320)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(.systemBackground))
                        )
                        .padding(.horizontal, 40)
                    }
                }
            }
            .overlay {
                if showingSignOutConfirm {
                    ZStack {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                        VStack(spacing: 16) {
                            Text("Sign Out")
                                .font(.headline)
                            Text("Are you sure you want to sign out?")
                                .multilineTextAlignment(.center)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            HStack {
                                Button("Cancel") {
                                    showingSignOutConfirm = false
                                }
                                .buttonStyle(.bordered)
                                Spacer()
                                Button("Sign Out") {
                                    authVM.signOut()
                                    showingSignOutConfirm = false
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                            }
                        }
                        .padding(24)
                        .frame(maxWidth: 320)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(.systemBackground))
                        )
                        .padding(.horizontal, 40)
                    }
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
                    .disabled(authVM.user == nil || authVM.currentProfile == nil)
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal)

            profileSwitcherSection

            if let profile = authVM.currentProfile {
                Group {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("My Lists")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        HStack {
                            Label("Favorites", systemImage: "heart.fill").foregroundStyle(.pink)
                            Spacer()
                            Text("\(profile.favoritesEntries.count)")
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Label("Watchlist", systemImage: "bookmark.fill").foregroundStyle(.blue)
                            Spacer()
                            Text("\(profile.watchlistEntries.count)")
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Label("Want to Read", systemImage: "book.pages.fill").foregroundStyle(.blue)
                            Spacer()
                            Text("\(profile.booksWantToReadEntries.count)")
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Label("Watched", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            Spacer()
                            Text("\(profile.watchedEntries.count)")
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Label("Read", systemImage: "book.fill").foregroundStyle(.green)
                            Spacer()
                            Text("\(profile.booksReadEntries.count)")
                                .foregroundStyle(.secondary)
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
            } else {
                
                Group {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("My Lists")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        HStack {
                            Label("Favorites", systemImage: "heart.fill").foregroundStyle(.pink)
                            Spacer()
                            Text("0")
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Label("Watchlist", systemImage: "bookmark.fill").foregroundStyle(.blue)
                            Spacer()
                            Text("0")
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Label("Watched", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            Spacer()
                            Text("0")
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Label("My Lists", systemImage: "list.bullet").foregroundStyle(.purple)
                            Spacer()
                            Text("0").foregroundStyle(.secondary)
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

    private var tabBarSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ListTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: tab.icon)
                                .imageScale(.small)
                            Text(tab.rawValue)
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(selectedTab == tab ? Color.white : tab.tint)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Capsule(style: .continuous)
                                .fill(selectedTab == tab ? tab.tint : Color(.secondarySystemBackground))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
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
                        NavigationLink { MediaDetailDestination(item: movie) } label: { row(for: movie) }
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
                                            Image(systemName: "trash.fill").foregroundStyle(selectedTab.tint)
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

    private var profileSwitcherSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Profiles")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if let user = authVM.user, !user.profiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(user.profiles) { profile in
                            Button {
                                authVM.selectProfile(profile.id)
                            } label: {
                                VStack(spacing: 8) {
                                    profileAvatar(for: profile, isSelected: profile.id == authVM.currentProfile?.id)
                                    Text(profileName(for: profile))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                        .frame(width: 78)
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            showingAddProfilePrompt = true
                        } label: {
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(Color(.secondarySystemBackground))
                                        .frame(width: 64, height: 64)
                                    Circle()
                                        .stroke(Color.accentColor.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                                        .frame(width: 64, height: 64)
                                    Image(systemName: "plus")
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundStyle(Color.accentColor)
                                }
                                Text("New Profile")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .frame(width: 78)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .disabled(authVM.user == nil)
                    }
                }
            } else {
                Text("No profile found yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
    }

    private func profileName(for profile: Profile) -> String {
        let trimmedName = profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedName.isEmpty ? "Profile" : trimmedName
    }

    @ViewBuilder
    private func profileAvatar(for profile: Profile, isSelected: Bool) -> some View {
        if let urlStr = profile.photoURL {
            if urlStr.hasPrefix("avatar://") {
                let id = String(urlStr.dropFirst("avatar://".count))
                Image(id)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                    }
            } else if let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        Circle().fill(Color(.tertiarySystemFill))
                            .frame(width: 64, height: 64)
                            .overlay { CustomLoadingView() }
                    case .success(let img):
                        img.resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(Circle())
                            .overlay {
                                Circle()
                                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                            }
                    case .failure:
                        profilePlaceholder(isSelected: isSelected)
                    @unknown default:
                        profilePlaceholder(isSelected: isSelected)
                    }
                }
            } else {
                profilePlaceholder(isSelected: isSelected)
            }
        } else {
            profilePlaceholder(isSelected: isSelected)
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
                        Image(systemName: "trash.fill").foregroundStyle(selectedTab.tint)
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

    

    private func currentFavoriteEntries() -> [WatchedEntry] {
        
        return authVM.currentProfile?.favoritesEntries ?? []
    }

    private func currentWatchlistEntries() -> [WatchedEntry] {
        
        return authVM.currentProfile?.watchlistEntries ?? []
    }

    private func currentWatchedEntries() -> [WatchedEntry] {
        
        return authVM.currentProfile?.watchedEntries ?? []
    }

    private func currentWantToReadEntries() -> [WatchedEntry] {
        authVM.currentProfile?.booksWantToReadEntries ?? []
    }

    private func currentReadBookEntries() -> [WatchedEntry] {
        authVM.currentProfile?.booksReadEntries ?? []
    }

    private func fetchMediaItems(from entries: [WatchedEntry]) async -> [Movie] {
        await withTaskGroup(of: (Int, Movie?).self) { group -> [Movie] in
            for entry in entries {
                group.addTask {
                    do {
                        let media = try await BookCatalog.fetchMedia(id: entry.id, type: entry.type, externalContentID: entry.externalID, service: service)
                        return (entry.id, media)
                    } catch {
                        return (entry.id, nil)
                    }
                }
            }
            var items: [(Int, Movie?)] = []
            while let next = await group.next() { items.append(next) }
            let map = Dictionary(uniqueKeysWithValues: items)
            let orderedMovies = entries.compactMap { map[$0.id] ?? nil }
            return orderedMovies.compactMap { $0 }
        }
    }

    

    private func startCustomListsListener(userId: String, profileId: String) {
        Task {
            await migrateLegacyCustomListsIfNeeded(userId: userId, profileId: profileId)
        }

        let ref = Firestore.firestore()
            .collection("users")
            .document(userId)
            .collection("profiles")
            .document(profileId)
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

    private func migrateLegacyCustomListsIfNeeded(userId: String, profileId: String) async {
        let db = Firestore.firestore()
        let userDocRef = db.collection("users").document(userId)
        let legacyListsRef = db.collection("users").document(userId).collection("lists")
        let profileListsRef = db.collection("users").document(userId)
            .collection("profiles").document(profileId)
            .collection("lists")

        do {
            let userDoc = try await userDocRef.getDocument()
            if userDoc.data()?["legacyCustomListsMigratedProfileID"] as? String != nil {
                return
            }

            let legacySnapshot = try await legacyListsRef.getDocuments()
            guard !legacySnapshot.documents.isEmpty else { return }

            for legacyDoc in legacySnapshot.documents {
                let targetDoc = profileListsRef.document(legacyDoc.documentID)
                let targetSnapshot = try await targetDoc.getDocument()

                if !targetSnapshot.exists {
                    try await targetDoc.setData(legacyDoc.data(), merge: true)
                }

                let legacyItems = try await legacyDoc.reference.collection("items").getDocuments()
                for itemDoc in legacyItems.documents {
                    try await targetDoc.collection("items").document(itemDoc.documentID).setData(itemDoc.data(), merge: true)
                }
            }

            try await userDocRef.setData([
                "legacyCustomListsMigratedProfileID": profileId
            ], merge: true)
        } catch {
            print("[Profile Lists] migration error:", error.localizedDescription)
        }
    }

    private func stopCustomListsListener() {
        listsListener?.remove()
        listsListener = nil
        userCustomLists = []
    }

    private func createProfile() async {
        let trimmedName = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        await authVM.addProfile(displayName: trimmedName, photoURL: nil)
        newProfileName = ""
    }

    
    private func createNewCustomList(name: String) async {
        guard let uid = authVM.user?.id, let profileId = authVM.currentProfile?.id else { return }
        let db = Firestore.firestore()
        
        let listsRef = db.collection("users").document(uid).collection("profiles").document(profileId).collection("lists")
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
        guard let uid = authVM.user?.id, let profileId = authVM.currentProfile?.id else { return }
        let db = Firestore.firestore()
        
        let docRef = db.collection("users").document(uid).collection("profiles").document(profileId).collection("lists").document(listID)
        do {
            try await docRef.delete()
        } catch {
            await MainActor.run { self.errorMessage = "Couldn't delete list. Please try again." }
        }
    }

    

    private func loadCurrentList(limitToFive: Bool) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        guard authVM.currentProfile != nil else {
            movies = []
            return
        }

        switch selectedTab {
        case .favorites:
            let entries = currentFavoriteEntries()
            guard !entries.isEmpty else { movies = []; return }
            let ordered = Array(entries.reversed())
            let limited = limitToFive ? Array(ordered.prefix(5)) : ordered
            movies = await fetchMediaItems(from: limited)

        case .watchlist:
            let entries = currentWatchlistEntries()
            guard !entries.isEmpty else { movies = []; return }
            let ordered = Array(entries.reversed())
            let limited = limitToFive ? Array(ordered.prefix(5)) : ordered
            movies = await fetchMediaItems(from: limited)

        case .watched:
            let entries = currentWatchedEntries()
            guard !entries.isEmpty else { movies = []; return }
            let ordered = Array(entries.reversed())
            let limited = limitToFive ? Array(ordered.prefix(5)) : ordered
            movies = await fetchMediaItems(from: limited)
        case .wantToReadBooks:
            let entries = Array(currentWantToReadEntries().reversed())
            let limited = limitToFive ? Array(entries.prefix(5)) : entries
            guard !limited.isEmpty else { movies = []; return }
            movies = await fetchMediaItems(from: limited)
        case .readBooks:
            let entries = Array(currentReadBookEntries().reversed())
            let limited = limitToFive ? Array(entries.prefix(5)) : entries
            guard !limited.isEmpty else { movies = []; return }
            movies = await fetchMediaItems(from: limited)
        case .custom:
            movies = []
            return
        }
    }

    private var showAllButton: Bool {
        
        guard let profile = authVM.currentProfile else { return false }
        switch selectedTab {
        case .favorites:
            return profile.favoritesEntries.count > 5
        case .watchlist:
            return profile.watchlistEntries.count > 5
        case .watched:
            return profile.watchedEntries.count > 5
        case .wantToReadBooks, .readBooks:
            return false
        case .custom:
            return false
        }
    }

    private func removeFromCurrentList(movieID: Int, mediaType: String?) async {
        guard authVM.currentProfile != nil else { return }
        switch selectedTab {
        case .favorites:
            await authVM.toggleFavorite(movieID: movieID, mediaType: mediaType ?? "movie")
        case .watchlist:
            await authVM.toggleWatchlist(movieID: movieID, mediaType: mediaType ?? "movie")
        case .watched:
            let type = mediaType ?? "movie"
            await authVM.toggleWatched(movieID: movieID, type: type)
        case .wantToReadBooks:
            await authVM.toggleWantToReadBook(movieID: movieID)
        case .readBooks:
            await authVM.toggleReadBook(movieID: movieID)
        case .custom:
            break
        }
        movies.removeAll { $0.id == movieID }
    }

    private var displayName: String {
        
        if let name = authVM.currentProfile?.displayName, !name.isEmpty { return name }
        return "User"
    }

    private var email: String {
        
        
        return authVM.user?.email ?? "-"
    }

    @ViewBuilder
    private var profileAvatar: some View {
        
        if let urlStr = authVM.currentProfile?.photoURL {
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
        profilePlaceholder(isSelected: false)
    }

    private func profilePlaceholder(isSelected: Bool) -> some View {
        Circle()
            .fill(Color(.tertiarySystemFill))
            .frame(width: 64, height: 64)
            .overlay {
                Image(systemName: "person.fill")
                    .foregroundStyle(.secondary)
            }
            .overlay {
                Circle()
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            }
    }
}

#Preview {
    ProfileView()
        .environmentObject(AuthViewModel())
}
