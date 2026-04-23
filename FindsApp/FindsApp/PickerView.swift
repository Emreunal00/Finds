import SwiftUI
import FirebaseFirestore

private let cardTransition: AnyTransition = .asymmetric(
    insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .center)).animation(.spring(response: 0.41, dampingFraction: 0.79)),
    removal: .opacity.combined(with: .scale(scale: 0.93, anchor: .center)).animation(.easeInOut(duration: 0.21))
)

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

    enum ContentKind: String, CaseIterable, Identifiable { case movies = "Movies", tv = "TV", books = "Books"; var id: String { rawValue } }
    @State private var kind: ContentKind = .movies

    @State private var localWatched: Set<String> = []
    @State private var localWatchlist: Set<String> = []
    @State private var localFavorites: Set<String> = []

    // Rating & Lists state
    @State private var isShowingRatingSheet: Bool = false
    @State private var tempRating: Double = 0
    @State private var userPreviousRating: Double? = nil

    @State private var isShowingListsSheet: Bool = false
    @State private var newListName: String = ""
    @State private var userLists: [CustomUserList] = []
    @State private var selectedLists: Set<String> = []
    @State private var listsListener: ListenerRegistration? = nil
    @State private var listPendingDeletion: CustomUserList? = nil

    // Track current profileId for custom lists usage
    @State private var currentProfileId: String? = nil

    private var isInAnyCustomListForCurrent: Bool {
        !selectedLists.isEmpty
    }

    // Helpers to reflect dynamic states (fallbacks if VM doesn't expose sets)
    private func isWatched(_ movie: Movie) -> Bool {
        let type = (movie.mediaType ?? "movie").lowercased()
        let key = "\(type):\(movie.id)"
        if localWatched.contains(key) { return true }
        if let checker = authVM as? (any AuthWatchChecking) {
            return checker.isWatched(movieID: movie.id, type: type)
        }
        if let setProvider = authVM as? (any AuthSetsProviding) {
            let ids: Set<Int> = setProvider.watchedIDs
            let mid: Int = movie.id
            return ids.contains(mid)
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
            let ids: Set<Int> = setProvider.watchlistIDs
            let mid: Int = movie.id
            return ids.contains(mid)
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
            let ids: Set<Int> = setProvider.favoriteIDs
            let mid: Int = movie.id
            return ids.contains(mid)
        }
        return false
    }

    @ViewBuilder
    private var mainContent: some View {
        if isLoading {
            CustomLoadingView(message: "Loading...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                Text("Failed to load").font(.headline)
                Text(error).font(.footnote).foregroundStyle(.secondary)
                Button("Try Again") { loadMovies() }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let movie = movies[safe: currentIndex] {
            contentForMovie(movie)
        } else {
            VStack(spacing: 16) {
                Image(systemName: kind == .books ? "book.closed" : "film")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text(kind == .books ? "No books available." : "No titles available.")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Button("Reload") { loadMovies() }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func contentForMovie(_ movie: Movie) -> some View {
        MovieContentView(movie: movie, dragOffset: $dragOffset, movies: $movies, currentIndex: $currentIndex, saveSwipeDecision: saveSwipeDecision, actionButtons: { m in actionButtons(for: m) })
    }

    @ViewBuilder
    private func actionButtons(for movie: Movie) -> some View {
        ActionButtonsView(
            movie: movie,
            prefersBookLabels: kind == .books,
            isWatched: isWatched(movie),
            isInWatchlist: isInWatchlist(movie),
            isFavorite: isFavorite(movie),
            isInAnyCustomListForCurrent: isInAnyCustomListForCurrent,
            userPreviousRating: userPreviousRating,
            localWatched: $localWatched,
            localWatchlist: $localWatchlist,
            localFavorites: $localFavorites,
            currentProfileId: currentProfileId,
            movies: $movies,
            currentIndex: $currentIndex,
            isShowingListsSheet: $isShowingListsSheet,
            isShowingRatingSheet: $isShowingRatingSheet,
            tempRating: $tempRating
        )
    }

    private struct MovieContentView: View {
        let movie: Movie
        @Binding var dragOffset: CGFloat
        @Binding var movies: [Movie]
        @Binding var currentIndex: Int
        let saveSwipeDecision: (Movie, PickerView.SwipeDecision) async -> Void
        let actionButtons: (Movie) -> AnyView

        init(movie: Movie, dragOffset: Binding<CGFloat>, movies: Binding<[Movie]>, currentIndex: Binding<Int>, saveSwipeDecision: @escaping (Movie, PickerView.SwipeDecision) async -> Void, actionButtons: @escaping (Movie) -> some View) {
            self.movie = movie
            self._dragOffset = dragOffset
            self._movies = movies
            self._currentIndex = currentIndex
            self.saveSwipeDecision = saveSwipeDecision
            self.actionButtons = { m in AnyView(actionButtons(m)) }
        }

        var body: some View {
            PosterCard(movie: movie,
                       dragOffset: $dragOffset,
                       onSwipeLeft: { swiped in
                           withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                               if !movies.isEmpty {
                                   _ = movies.remove(at: currentIndex)
                                   currentIndex = min(currentIndex, max(movies.count - 1, 0))
                               }
                           }
                           Task { await saveSwipeDecision(swiped, .not_recommend) }
                       },
                       onSwipeRight: { swiped in
                           withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                               if !movies.isEmpty {
                                   _ = movies.remove(at: currentIndex)
                                   currentIndex = min(currentIndex, max(movies.count - 1, 0))
                               }
                           }
                           Task { await saveSwipeDecision(swiped, .recommend) }
                       })
                .id(movie.id)
                .transition(cardTransition)
                .animation(.spring(response: 0.40, dampingFraction: 0.85), value: movie.id)

            NavigationLink { MediaDetailDestination(item: movie) } label: {
                Text(movie.title)
                    .font(.title2).bold()
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)

            actionButtons(movie)

            if !movie.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(movie.summary)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .padding(.top, 8)
                    .padding(.horizontal, 16)
            }
        }
    }

    private struct ActionButtonsView: View {
        let movie: Movie
        let prefersBookLabels: Bool
        let isWatched: Bool
        let isInWatchlist: Bool
        let isFavorite: Bool
        let isInAnyCustomListForCurrent: Bool
        let userPreviousRating: Double?
        @Binding var localWatched: Set<String>
        @Binding var localWatchlist: Set<String>
        @Binding var localFavorites: Set<String>
        @EnvironmentObject var authVM: AuthViewModel
        let currentProfileId: String?
        @Binding var movies: [Movie]
        @Binding var currentIndex: Int
        @Binding var isShowingListsSheet: Bool
        @Binding var isShowingRatingSheet: Bool
        @Binding var tempRating: Double

        private var watchedLabel: String {
            prefersBookLabels || movie.isBook ? "Read" : "Watched"
        }

        private var watchlistLabel: String {
            prefersBookLabels || movie.isBook ? "Want to Read" : "Watchlist"
        }

        private func watchedButton() -> some View {
            Button {
                let type = (movie.mediaType ?? "movie").lowercased()
                let key = "\(type):\(movie.id)"
                if localWatched.contains(key) { localWatched.remove(key) } else { localWatched.insert(key) }
                Task {
                    if movie.isBook {
                        await authVM.toggleReadBook(movieID: movie.id, externalContentID: movie.externalContentID)
                    } else {
                        await authVM.toggleWatched(movieID: movie.id, type: type, externalContentID: movie.externalContentID)
                    }
                }
            } label: {
                Label(watchedLabel, systemImage: isWatched ? "checkmark.circle.fill" : "checkmark.circle")
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(isWatched ? .green : .secondary)
            .disabled(authVM.user == nil)
        }

        private func watchlistButton() -> some View {
            Button {
                let type = (movie.mediaType ?? "movie").lowercased()
                let key = "\(type):\(movie.id)"
                if localWatchlist.contains(key) { localWatchlist.remove(key) } else { localWatchlist.insert(key) }
                Task {
                    if movie.isBook {
                        await authVM.toggleWantToReadBook(movieID: movie.id, externalContentID: movie.externalContentID)
                    } else {
                        await authVM.toggleWatchlist(movieID: movie.id, mediaType: type, externalContentID: movie.externalContentID)
                    }
                }
            } label: {
                Label(watchlistLabel, systemImage: isInWatchlist ? "bookmark.fill" : "bookmark")
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(isInWatchlist ? .blue : .secondary)
            .disabled(authVM.user == nil)
        }

        private func favoriteButton() -> some View {
            Button {
                let type = (movie.mediaType ?? "movie").lowercased()
                let key = "\(type):\(movie.id)"
                if localFavorites.contains(key) { localFavorites.remove(key) } else { localFavorites.insert(key) }
                Task { await authVM.toggleFavorite(movieID: movie.id, mediaType: type, externalContentID: movie.externalContentID) }
            } label: {
                Label(isFavorite ? "Favorite" : "Favorite", systemImage: isFavorite ? "heart.fill" : "heart")
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(isFavorite ? .pink : .secondary)
            .disabled(authVM.user == nil)
        }

        private func listsButton() -> some View {
            Button {
                isShowingListsSheet = true
                if let _ = authVM.user?.id, let _ = currentProfileId {
                    let type = (movie.mediaType ?? "movie").lowercased()
                    _ = type
                } else {
                    selectedListsReset()
                }
            } label: {
                Label(isInAnyCustomListForCurrent ? "In Lists" : "Add to List", systemImage: isInAnyCustomListForCurrent ? "text.badge.checkmark" : "text.badge.plus")
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(isInAnyCustomListForCurrent ? .purple : .secondary)
            .disabled(authVM.user == nil || movies[safe: currentIndex] == nil)
        }

        private func ratingButton() -> some View {
            Button {
                if movies[safe: currentIndex] != nil {
                    tempRating = userPreviousRating ?? tempRating
                    isShowingRatingSheet = true
                }
            } label: {
                if userPreviousRating != nil {
                    Label(String(format: "Rated"), systemImage: "star.fill")
                        .labelStyle(.titleAndIcon)
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Rate", systemImage: "star")
                        .labelStyle(.titleAndIcon)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .tint(userPreviousRating != nil ? .yellow : .secondary)
            .disabled(authVM.user == nil || movies[safe: currentIndex] == nil)
        }

        var body: some View {
            let columns: [GridItem] = [
                GridItem(.flexible(minimum: 120), spacing: 12),
                GridItem(.flexible(minimum: 120), spacing: 12)
            ]
            LazyVGrid(columns: columns, alignment: .center, spacing: 12) {
                watchedButton()
                watchlistButton()
                favoriteButton()
                listsButton()
                ratingButton()
            }
        }

        private func selectedListsReset() {
            // This method is intentionally left as a placeholder to match previous behavior
            // Actual reset happens in the parent when missing profile info.
        }
    }

    private struct PosterCard: View {
        let movie: Movie
        @Binding var dragOffset: CGFloat
        var onSwipeLeft: (Movie) -> Void
        var onSwipeRight: (Movie) -> Void

        var body: some View {
            let rotation: Angle = .degrees(Double(dragOffset) / 20)
            let scale: CGFloat = 1 - min(abs(dragOffset) / 1200, 0.08)
            return ZStack {
                AsyncImage(url: movie.posterURL) { phase in
                    switch phase {
                    case .empty: CustomLoadingView()
                    case .success(let image): image.resizable().scaledToFill()
                    case .failure:
                        Image(systemName: BookCatalog.symbolName(for: movie))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 56, height: 68)
                            .foregroundStyle(.secondary)
                    @unknown default: EmptyView()
                    }
                }
                .frame(width: 320, height: 500)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation.width
                    }
                    .onEnded { _ in
                        let threshold: CGFloat = 90
                        if dragOffset < -threshold {
                            onSwipeLeft(movie)
                        } else if dragOffset > threshold {
                            onSwipeRight(movie)
                        }
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { dragOffset = 0 }
                    }
            )
            .animation(.interactiveSpring(), value: dragOffset)
            .transition(cardTransition)
            .offset(x: dragOffset)
            .rotationEffect(rotation)
            .scaleEffect(scale)
        }
    }

    private struct KindSegmentedPicker: View {
        @Binding var kind: PickerView.ContentKind
        var body: some View {
            Picker("Kind", selection: $kind) {
                ForEach(PickerView.ContentKind.allCases) { k in
                    Text(k.rawValue).tag(k)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
            .id("KindSegmentedPickerID")
        }
    }

    private var principalToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            KindSegmentedPicker(kind: $kind)
        }
    }

    private var swipeGlowBackground: some View {
        ZStack {
            let dragRatio = min(abs(dragOffset) / 120, 1.0)
            let baseOpacity = max(0, Double(dragRatio))
            let leftOpacity = baseOpacity * (dragOffset < 0 ? 1 : 0)
            let rightOpacity = baseOpacity * (dragOffset > 0 ? 1 : 0)

            LinearGradient(
                colors: [Color.red.opacity(0.45), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .opacity(leftOpacity)
            .ignoresSafeArea()

            LinearGradient(
                colors: [Color.clear, Color.green.opacity(0.45)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .opacity(rightOpacity)
            .ignoresSafeArea()
        }
    }

    private struct ListsSheetView: View {
        @EnvironmentObject var authVM: AuthViewModel
        @Binding var currentProfileId: String?
        @Binding var userLists: [CustomUserList]
        @Binding var selectedLists: Set<String>
        @Binding var newListName: String
        @Binding var listPendingDeletion: CustomUserList?
        @Binding var isShowingListsSheet: Bool
        let currentMovie: Movie?

        let startListsListener: (String, String, Movie) -> Void
        let loadSelections: (String, String, Movie) async -> Void
        let addNewList: (String, String, String) async -> Void
        let saveSelections: (String, String, Movie) async -> Void
        let deleteList: (String, String, String) async -> Void

        private struct ListRowView: View {
            let list: CustomUserList
            let isSelected: Bool
            let onToggle: () -> Void
            let onDelete: () -> Void
            var body: some View {
                HStack(spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.green : Color.secondary)
                        .imageScale(.large)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(list.name).font(.body)
                        if isSelected { Text("Selected").font(.caption2).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .imageScale(.medium)
                    }
                    .accessibilityLabel("Delete list")
                }
                .contentShape(Rectangle())
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(Rectangle().fill(Color(.secondarySystemBackground)).opacity(0.001))
                .onTapGesture { onToggle() }
            }
        }

        var body: some View {
            NavigationStack {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Add to Lists").font(.title3.weight(.semibold))
                        Text("Select the lists to include this title. You can also create a new list.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.top, 16)

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search lists", text: .constant(""))
                            .textFieldStyle(.plain)
                            .disabled(true)
                    }
                    .padding(10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.horizontal)
                    .padding(.top, 12)

                    Group {
                        if userLists.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "list.bullet.rectangle").font(.system(size: 28)).foregroundStyle(.secondary)
                                Text("No lists yet").font(.headline)
                                Text("Create your first list below.").font(.footnote).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(userLists) { list in
                                        let isSelected = selectedLists.contains(list.id)
                                        ListRowView(list: list, isSelected: isSelected) {
                                            if selectedLists.contains(list.id) { selectedLists.remove(list.id) } else { selectedLists.insert(list.id) }
                                            if let uid = authVM.user?.id, let profileId = currentProfileId, let movie = currentMovie {
                                                Task { await saveSelections(uid, profileId, movie) }
                                            }
                                        } onDelete: {
                                            listPendingDeletion = list
                                        }
                                        Divider().padding(.leading, 48)
                                    }
                                }
                            }
                            .padding(.top, 8)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            TextField("Create new list", text: $newListName)
                                .textFieldStyle(.roundedBorder)
                            Button("Add") {
                                Task {
                                    if let uid = authVM.user?.id, let profileId = currentProfileId {
                                        await addNewList(uid, profileId, newListName)
                                    }
                                    newListName = ""
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)

                    HStack(spacing: 12) {
                        Button("Cancel") { isShowingListsSheet = false }
                            .buttonStyle(.bordered)
                        Spacer()
                        Button("Save") {
                            Task {
                                if let uid = authVM.user?.id, let profileId = currentProfileId, let movie = currentMovie {
                                    await saveSelections(uid, profileId, movie)
                                }
                                isShowingListsSheet = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                }
                .navigationTitle("Lists")
                .navigationBarTitleDisplayMode(.inline)
                .alert("Delete list?", isPresented: Binding(get: { listPendingDeletion != nil }, set: { if !$0 { listPendingDeletion = nil } })) {
                    Button("Delete", role: .destructive) {
                        if let uid = authVM.user?.id, let profileId = currentProfileId, let pending = listPendingDeletion {
                            Task { await deleteList(uid, profileId, pending.id) }
                        }
                        listPendingDeletion = nil
                    }
                    Button("Cancel", role: .cancel) { listPendingDeletion = nil }
                } message: {
                    if let pending = listPendingDeletion {
                        Text("Are you sure you want to delete \(pending.name)? This action cannot be undone.")
                    } else {
                        Text("Are you sure you want to delete this list? This action cannot be undone.")
                    }
                }
            }
            .onAppear {
                if let uid = authVM.user?.id, let profileId = currentProfileId, let movie = currentMovie {
                    startListsListener(uid, profileId, movie)
                    Task { await loadSelections(uid, profileId, movie) }
                } else {
                    selectedLists = []
                    userLists = []
                }
            }
            .onDisappear {
                // The listener is managed by the parent view; nothing to remove here.
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private struct RatingSheetView: View {
        let currentMovie: Movie?
        @Binding var tempRating: Double
        @Binding var userPreviousRating: Double?
        @Binding var isShowingRatingSheet: Bool
        let submitRating: (Double) async -> Void
        let removeRating: () async -> Void

        private func actionButtons() -> some View {
            HStack(spacing: 12) {
                Button("Cancel") { isShowingRatingSheet = false }
                    .buttonStyle(.bordered)
                Button("Save") {
                    isShowingRatingSheet = false
                    Task { await submitRating(tempRating) }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                if userPreviousRating != nil {
                    Button(role: .destructive) {
                        isShowingRatingSheet = false
                        Task { await removeRating() }
                    } label: { Text("Remove Rating") }
                }
            }
        }

        var body: some View {
            VStack(spacing: 16) {
                if let movie = currentMovie {
                    Spacer(minLength: 20)
                    Text(movie.title)
                        .font(.title3.weight(.bold))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity)
                    Text("Rate this title")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    StarRatingView(rating: $tempRating, starSize: 48)
                        .frame(height: 58)
                    actionButtons()
                }
            }
            .padding()
            .presentationDetents([.height(255), .medium])
        }
    }

    private var pickerScrollContent: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 0)
                mainContent
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var ratingSheetContent: some View {
        RatingSheetView(
            currentMovie: movies[safe: currentIndex],
            tempRating: $tempRating,
            userPreviousRating: $userPreviousRating,
            isShowingRatingSheet: $isShowingRatingSheet,
            submitRating: submitRating,
            removeRating: removeRating
        )
    }

    @ViewBuilder
    private var listsSheetContent: some View {
        ListsSheetView(
            currentProfileId: $currentProfileId,
            userLists: $userLists,
            selectedLists: $selectedLists,
            newListName: $newListName,
            listPendingDeletion: $listPendingDeletion,
            isShowingListsSheet: $isShowingListsSheet,
            currentMovie: movies[safe: currentIndex],
            startListsListener: startListsListener,
            loadSelections: loadSelections,
            addNewList: addNewList,
            saveSelections: saveSelections,
            deleteList: deleteList
        )
        .environmentObject(authVM)
    }

    private func handleAppear() {
        if authVM.user != nil {
            currentProfileId = authVM.currentProfile?.id
        } else {
            currentProfileId = nil
        }

        refreshListsAndRatingsIfPossible()
    }

    private func handleKindChange() {
        movies = []
        currentIndex = 0
        loadMoviesForCurrentKind()
        Task { @MainActor in
            refreshListsAndRatingsIfPossible()
        }
    }

    private var navigationContent: some View {
        NavigationStack {
            pickerScrollContent
            .background(swipeGlowBackground)
            .navigationTitle("Picker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                principalToolbar
            }
            .onAppear {
                handleAppear()
            }
            .onChange(of: currentProfileId) { _ in
                refreshListsAndRatingsIfPossible()
            }
            .onChange(of: currentIndex) { _ in
                refreshListsAndRatingsIfPossible()
            }
            .onChange(of: movies) { _ in
                refreshListsAndRatingsIfPossible()
            }
            .onDisappear { listsListener?.remove(); listsListener = nil }
            .sheet(isPresented: $isShowingRatingSheet) {
                ratingSheetContent
            }
            .sheet(isPresented: $isShowingListsSheet) {
                listsSheetContent
            }
        }
    }

    var body: some View {
        navigationContent
        .task {
            if movies.isEmpty { loadMovies() }
            // Preload list selections for current movie if available
            refreshListsAndRatingsIfPossible()
        }
        .onChange(of: kind) { _ in
            handleKindChange()
        }
    }
    
    // MARK: - Swipe decisions persistence
    private enum SwipeDecision: String { case recommend, not_recommend }

    private func saveSwipeDecision(for movie: Movie, decision: SwipeDecision) async {
        guard let uid = authVM.user?.id else { return }
        let type = (movie.mediaType ?? "movie").lowercased()
        let key = "\(type):\(movie.id)"
        let db = Firestore.firestore()

        // Write ONLY to specific collections
        let targetCollection = (decision == .recommend) ? "pickerDecisionsRecommended" : "pickerDecisionsNotRecommended"
        let targetDoc = db.collection("users").document(uid).collection(targetCollection).document(key)

        do {
            try await targetDoc.setData([
                "movieId": movie.id,
                "type": type,
                "externalContentID": movie.externalContentID as Any,
                "decidedAt": FieldValue.serverTimestamp()
            ], merge: true)
        } catch {
            print("[Picker Swipe] save failed:", error.localizedDescription)
        }

        // Clean up legacy common collection if present (no longer needed)
        let legacyCommon = db.collection("users").document(uid).collection("pickerDecisions").document(key)
        do { try await legacyCommon.delete() } catch { /* ignore if not exists */ }
    }

    // MARK: - Lists helpers
    // NOTE: New Firestore structure: users/{userId}/profiles/{profileId}/lists/{listId}
    // All functions below require profileId, and will abort or clear UI if missing.

    private func startListsListener(userId: String, profileId: String, movie: Movie) {
        let ref = Firestore.firestore()
            .collection("users")
            .document(userId)
            .collection("profiles")
            .document(profileId)
            .collection("lists")
            .order(by: "createdAt", descending: false)
        listsListener?.remove()
        listsListener = ref.addSnapshotListener { snapshot, error in
            if let error = error {
                print("[Picker Lists] listener error:", error.localizedDescription)
                return
            }
            guard let docs = snapshot?.documents else { return }
            let lists = docs.map { doc -> CustomUserList in
                let name = doc.data()["name"] as? String ?? "Untitled"
                return CustomUserList(id: doc.documentID, name: name)
            }
            self.userLists = lists
            Task { await loadSelections(userId: userId, profileId: profileId, movie: movie) }
        }
    }

    private func loadSelections(userId: String, profileId: String, movie: Movie) async {
        guard !userLists.isEmpty else {
            await MainActor.run {
                self.selectedLists = []
            }
            return
        }
        let type = (movie.mediaType ?? "movie").lowercased()
        let db = Firestore.firestore()
        var newSelected: Set<String> = []
        for list in userLists {
            let itemRef = db.collection("users").document(userId)
                .collection("profiles").document(profileId)
                .collection("lists").document(list.id)
                .collection("items").document("\(type):\(movie.id)")
            do {
                let snap = try await itemRef.getDocument()
                if snap.exists { newSelected.insert(list.id) }
            } catch {
                print("[Picker Lists] load selection error for \(list.id):", error.localizedDescription)
            }
        }
        await MainActor.run { self.selectedLists = newSelected }
    }

    private func addNewList(userId: String, profileId: String, name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let db = Firestore.firestore()
        do {
            let ref = db.collection("users").document(userId)
                .collection("profiles").document(profileId)
                .collection("lists").document()
            try await ref.setData([
                "name": trimmed,
                "createdAt": FieldValue.serverTimestamp()
            ])
        } catch {
            print("[Picker Lists] add error:", error.localizedDescription)
        }
    }

    private func saveSelections(userId: String, profileId: String, movie: Movie) async {
        let type = (movie.mediaType ?? "movie").lowercased()
        let db = Firestore.firestore()
        let key = "\(type):\(movie.id)"
        for list in userLists {
            let itemRef = db.collection("users").document(userId)
                .collection("profiles").document(profileId)
                .collection("lists").document(list.id)
                .collection("items").document(key)
            do {
                if selectedLists.contains(list.id) {
                    try await itemRef.setData([
                        "movieId": movie.id,
                        "type": type,
                        "externalContentID": movie.externalContentID as Any,
                        "addedAt": FieldValue.serverTimestamp()
                    ])
                } else {
                    try await itemRef.delete()
                }
            } catch {
                print("[Picker Lists] save item error for \(list.id):", error.localizedDescription)
            }
        }
    }
    
    private func deleteList(userId: String, profileId: String, listID: String) async {
        let db = Firestore.firestore()
        do {
            try await db.collection("users").document(userId)
                .collection("profiles").document(profileId)
                .collection("lists").document(listID).delete()
            // If the deleted list was selected, remove it locally
            await MainActor.run { self.selectedLists.remove(listID) }
        } catch {
            print("[Picker Lists] delete error for list=\(listID):", error.localizedDescription)
        }
    }

    // New helper added here:
    private func fetchRecentlyDislikedIDs(uid: String) async -> Set<Int> {
        let db = Firestore.firestore()
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        let cutoff = Timestamp(date: sevenDaysAgo)
        do {
            let snap = try await db.collection("users").document(uid)
                .collection("pickerDecisionsNotRecommended")
                .whereField("decidedAt", isGreaterThanOrEqualTo: cutoff)
                .getDocuments()
            let ids: Set<Int> = Set(snap.documents.compactMap { $0.data()["movieId"] as? Int })
            return ids
        } catch {
            print("[Picker Filter] fetch disliked failed:", error.localizedDescription)
            return []
        }
    }
    
    // MARK: - Rating helpers with profile-specific Firestore storage
    
    private func fetchUserRatingForCurrent() async {
        // Changed to profile-specific rating storage
        guard let uid = authVM.user?.id, let profileId = currentProfileId, let movie = movies[safe: currentIndex] else { return }
        let type = (movie.mediaType ?? "movie").lowercased()
        let db = Firestore.firestore()
        let docRef = db.collection("users")
            .document(uid)
            .collection("profiles")
            .document(profileId)
            .collection("ratings")
            .document("\(type):\(movie.id)")
        do {
            let snap = try await docRef.getDocument()
            if let val = snap.data()?["rating"] as? Double {
                await MainActor.run {
                    self.userPreviousRating = val
                    self.tempRating = val
                }
            } else {
                await MainActor.run {
                    self.userPreviousRating = nil
                    self.tempRating = 0
                }
            }
        } catch {
            print("[Picker Rating] fetch user rating failed:", error.localizedDescription)
        }
    }

    private func submitRating(_ value: Double) async {
        // Changed to profile-specific rating storage
        guard let uid = authVM.user?.id, let profileId = currentProfileId, let movie = movies[safe: currentIndex] else { return }
        let type = (movie.mediaType ?? "movie").lowercased()
        let db = Firestore.firestore()
        let docRef = db.collection("users")
            .document(uid)
            .collection("profiles")
            .document(profileId)
            .collection("ratings")
            .document("\(type):\(movie.id)")
        do {
            try await docRef.setData([
                "rating": value,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
            await MainActor.run {
                self.userPreviousRating = value
            }
            // Optionally print debug info
            print("[Picker Rating] submit success for profile-specific rating")
        } catch {
            print("[Picker Rating] submit failed:", error.localizedDescription)
        }
    }

    private func removeRating() async {
        // Changed to profile-specific rating storage
        guard let uid = authVM.user?.id, let profileId = currentProfileId, let movie = movies[safe: currentIndex], let _ = userPreviousRating else { return }
        let type = (movie.mediaType ?? "movie").lowercased()
        let db = Firestore.firestore()
        let docRef = db.collection("users")
            .document(uid)
            .collection("profiles")
            .document(profileId)
            .collection("ratings")
            .document("\(type):\(movie.id)")
        do {
            try await docRef.delete()
            await MainActor.run {
                self.userPreviousRating = nil
                self.tempRating = 0
            }
            print("[Picker Rating] remove success for profile-specific rating")
        } catch {
            print("[Picker Rating] remove failed:", error.localizedDescription)
            await MainActor.run {
                self.userPreviousRating = nil
                self.tempRating = 0
            }
        }
    }

    // Centralized refresh helper to reduce repeated complex closures
    private func refreshListsAndRatingsIfPossible() {
        if let uid = authVM.user?.id,
           let profileId = currentProfileId,
           let movie = movies[safe: currentIndex] {
            startListsListener(userId: uid, profileId: profileId, movie: movie)
            Task {
                await loadSelections(userId: uid, profileId: profileId, movie: movie)
                await fetchUserRatingForCurrent()
            }
        } else {
            selectedLists = []
            userLists = []
        }
    }
    
    private func loadMovies() {
        loadMoviesForCurrentKind()
    }
    
    private func loadMoviesForCurrentKind() {
        isLoading = true
        error = nil
        Task {
            do {
                switch kind {
                case .movies:
                    let pages: [Int] = Array(1...10)
                    var results: [[Movie]] = []
                    try await withThrowingTaskGroup(of: [Movie].self) { group in
                        for p in pages {
                            group.addTask {
                                let svc = MovieService()
                                return try await svc.getTrending(page: p)
                            }
                        }
                        for try await res in group {
                            results.append(res)
                        }
                    }
                    // Flatten results
                    var combined: [Movie] = []
                    for pageResults in results {
                        combined.append(contentsOf: pageResults)
                    }
                    // Deduplicate by id
                    var seen: Set<Int> = []
                    var deduped: [Movie] = []
                    for m in combined {
                        if !seen.contains(m.id) {
                            seen.insert(m.id)
                            deduped.append(m)
                        }
                    }
                    // Shuffle after dedupe
                    var shuffled = deduped
                    shuffled.shuffle()
                    // Filter out recently disliked
                    let filtered: [Movie]
                    if let uid = authVM.user?.id {
                        let disliked = await fetchRecentlyDislikedIDs(uid: uid)
                        filtered = shuffled.filter { movie in !disliked.contains(movie.id) }
                    } else {
                        filtered = shuffled
                    }
                    await MainActor.run {
                        self.movies = filtered
                    }
                case .tv:
                    let pages: [Int] = Array(1...10)
                    var results: [[Movie]] = []
                    try await withThrowingTaskGroup(of: [Movie].self) { group in
                        for p in pages {
                            group.addTask {
                                let svc = MovieService()
                                return try await svc.getTrendingTV(page: p)
                            }
                        }
                        for try await res in group {
                            results.append(res)
                        }
                    }
                    // Flatten results
                    var combined: [Movie] = []
                    for pageResults in results {
                        combined.append(contentsOf: pageResults)
                    }
                    // Deduplicate by id
                    var seen: Set<Int> = []
                    var deduped: [Movie] = []
                    for m in combined {
                        if !seen.contains(m.id) {
                            seen.insert(m.id)
                            deduped.append(m)
                        }
                    }
                    // Shuffle after dedupe
                    var shuffled = deduped
                    shuffled.shuffle()
                    // Filter out recently disliked
                    let filtered: [Movie]
                    if let uid = authVM.user?.id {
                        let disliked = await fetchRecentlyDislikedIDs(uid: uid)
                        filtered = shuffled.filter { movie in !disliked.contains(movie.id) }
                    } else {
                        filtered = shuffled
                    }
                    await MainActor.run {
                        self.movies = filtered
                    }
                case .books:
                    let books = await BookCatalog.trendingBooks(page: Int.random(in: 1...5)).shuffled()
                    let filtered: [Movie]
                    if let uid = authVM.user?.id {
                        let disliked = await fetchRecentlyDislikedIDs(uid: uid)
                        filtered = books.filter { !disliked.contains($0.id) }
                    } else {
                        filtered = books
                    }
                    await MainActor.run {
                        self.movies = filtered
                    }
                }
                await MainActor.run {
                    if let user = authVM.user, let profile = authVM.currentProfile {
                        self.localWatched = Set(
                            profile.watchedEntries.map { "\($0.type.lowercased()):\($0.id)" } +
                            profile.booksReadEntries.map { "\($0.type.lowercased()):\($0.id)" }
                        )
                        self.localWatchlist = Set(
                            profile.watchlistEntries.map { "\($0.type.lowercased()):\($0.id)" } +
                            profile.booksWantToReadEntries.map { "\($0.type.lowercased()):\($0.id)" }
                        )
                        self.localFavorites = Set(profile.favoritesEntries.map { "\($0.type.lowercased()):\($0.id)" })
                        self.currentProfileId = profile.id
                    } else {
                        self.localWatched = []
                        self.localWatchlist = []
                        self.localFavorites = []
                        self.currentProfileId = nil
                    }
                }
                await MainActor.run {
                    if let uid = authVM.user?.id,
                       let profileId = currentProfileId,
                       let first = self.movies[safe: self.currentIndex] {
                        startListsListener(userId: uid, profileId: profileId, movie: first)
                        Task {
                            await loadSelections(userId: uid, profileId: profileId, movie: first)
                            await fetchUserRatingForCurrent()
                        }
                    } else {
                        self.selectedLists = []
                        self.userLists = []
                    }
                    self.currentIndex = min(self.currentIndex, max(self.movies.count - 1, 0))
                    self.isLoading = false
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
