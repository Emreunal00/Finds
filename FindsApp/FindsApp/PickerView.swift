import SwiftUI
import FirebaseFirestore

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

    enum ContentKind: String, CaseIterable, Identifiable { case movies = "Movies", tv = "TV"; var id: String { rawValue } }
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
            ScrollView {
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
                                    // Capture the movie being swiped BEFORE we mutate the array/index
                                    let swipedMovie = movies[safe: currentIndex]

                                    if dragOffset < -threshold {
                                        // Swiped left (dislike)
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                            if !movies.isEmpty {
                                                _ = movies.remove(at: currentIndex)
                                                currentIndex = min(currentIndex, max(movies.count - 1, 0))
                                            }
                                        }
                                        if let movie = swipedMovie {
                                            Task { await saveSwipeDecision(for: movie, decision: .not_recommend) }
                                        }
                                    } else if dragOffset > threshold {
                                        // Swiped right (like)
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                            if !movies.isEmpty {
                                                _ = movies.remove(at: currentIndex)
                                                currentIndex = min(currentIndex, max(movies.count - 1, 0))
                                            }
                                        }
                                        if let movie = swipedMovie {
                                            Task { await saveSwipeDecision(for: movie, decision: .recommend) }
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
                        // Action buttons (2-column grid for readability)
                        let columns = [GridItem(.flexible(minimum: 120), spacing: 12), GridItem(.flexible(minimum: 120), spacing: 12)]
                        LazyVGrid(columns: columns, alignment: .center, spacing: 12) {
                            Button {
                                let type = (movie.mediaType ?? "movie").lowercased()
                                let key = "\(type):\(movie.id)"
                                if localWatched.contains(key) { localWatched.remove(key) } else { localWatched.insert(key) }
                                Task { await authVM.toggleWatched(movieID: movie.id, type: type) }
                            } label: {
                                Label(isWatched(movie) ? "Watched" : "Watched", systemImage: isWatched(movie) ? "checkmark.circle.fill" : "checkmark.circle")
                                    .labelStyle(.titleAndIcon)
                                    .frame(maxWidth: .infinity)
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
                                    .frame(maxWidth: .infinity)
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
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(isFavorite(movie) ? .pink : .secondary)
                            .disabled(authVM.user == nil)

                            Button {
                                isShowingListsSheet = true
                                if let movie = movies[safe: currentIndex], let uid = authVM.user?.id { startListsListener(uid: uid, movie: movie) }
                            } label: {
                                Label(isInAnyCustomListForCurrent ? "In Lists" : "Add to List",
                                      systemImage: isInAnyCustomListForCurrent ? "text.badge.checkmark" : "text.badge.plus")
                                    .labelStyle(.titleAndIcon)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(isInAnyCustomListForCurrent ? .purple : .secondary)
                            .disabled(authVM.user == nil || movies[safe: currentIndex] == nil)

                            Button {
                                if let _ = movies[safe: currentIndex] {
                                    tempRating = userPreviousRating ?? tempRating
                                    isShowingRatingSheet = true
                                }
                            } label: {
                                if let ur = userPreviousRating {
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
                        .font(.subheadline)
                        .padding(.horizontal, 8)

                        if !movie.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(movie.summary)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .padding(.top, 8)
                                .padding(.horizontal, 16)
                        }
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
            .navigationTitle("Picker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Kind", selection: $kind) {
                        ForEach(ContentKind.allCases) { k in
                            Text(k.rawValue).tag(k)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
            }
            .onAppear {
                if let uid = authVM.user?.id, let movie = movies[safe: currentIndex] {
                    startListsListener(uid: uid, movie: movie)
                    Task {
                        await loadSelections(uid: uid, movie: movie)
                        await fetchUserRatingForCurrent()
                    }
                }
            }
            .onChange(of: currentIndex) { _ in
                if let uid = authVM.user?.id, let movie = movies[safe: currentIndex] {
                    startListsListener(uid: uid, movie: movie)
                    Task {
                        await loadSelections(uid: uid, movie: movie)
                        await fetchUserRatingForCurrent()
                    }
                } else {
                    // Clear selection if no movie
                    selectedLists = []
                }
            }
            .onChange(of: movies) { _ in
                if let uid = authVM.user?.id, let movie = movies[safe: currentIndex] {
                    startListsListener(uid: uid, movie: movie)
                    Task {
                        await loadSelections(uid: uid, movie: movie)
                        await fetchUserRatingForCurrent()
                    }
                } else {
                    selectedLists = []
                }
            }
            .onDisappear { listsListener?.remove(); listsListener = nil }
            .sheet(isPresented: $isShowingRatingSheet) {
                VStack(spacing: 16) {
                    if let movie = movies[safe: currentIndex] {
                        Text("Rate \(movie.title)").font(.headline)
                        StarRatingView(rating: $tempRating, starSize: 50)
                            .frame(height: 70)
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
                }
                .padding()
                .presentationDetents([.height(220), .medium])
            }
            .sheet(isPresented: $isShowingListsSheet) {
                NavigationStack {
                    VStack(spacing: 0) {
                        // Header
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Add to Lists").font(.title3.weight(.semibold))
                            Text("Select the lists to include this title. You can also create a new list.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                        .padding(.top, 16)

                        // Search (placeholder for now)
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

                        // Lists
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
                                                    listPendingDeletion = list
                                                } label: {
                                                    Image(systemName: "trash")
                                                        .imageScale(.medium)
                                                }
                                                .accessibilityLabel("Delete list")
                                            }
                                            .contentShape(Rectangle())
                                            .padding(.horizontal)
                                            .padding(.vertical, 12)
                                            .background(
                                                Rectangle().fill(Color(.secondarySystemBackground)).opacity(0.001)
                                            )
                                            .onTapGesture {
                                                if selectedLists.contains(list.id) { selectedLists.remove(list.id) } else { selectedLists.insert(list.id) }
                                                if let uid = authVM.user?.id, let movie = movies[safe: currentIndex] {
                                                    Task { await saveSelections(uid: uid, movie: movie) }
                                                }
                                            }
                                            Divider().padding(.leading, 48)
                                        }
                                    }
                                }
                                .padding(.top, 8)
                            }
                        }

                        // Create new list
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                TextField("Create new list", text: $newListName)
                                    .textFieldStyle(.roundedBorder)
                                Button("Add") {
                                    Task {
                                        if let uid = authVM.user?.id { await addNewList(uid: uid, name: newListName) }
                                        newListName = ""
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)

                        // Bottom bar
                        HStack(spacing: 12) {
                            Button("Cancel") { isShowingListsSheet = false }
                                .buttonStyle(.bordered)
                            Spacer()
                            Button("Save") {
                                Task {
                                    if let uid = authVM.user?.id, let movie = movies[safe: currentIndex] {
                                        await saveSelections(uid: uid, movie: movie)
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
                    .alert("Delete list?", isPresented: Binding(
                        get: { listPendingDeletion != nil },
                        set: { if !$0 { listPendingDeletion = nil } }
                    )) {
                        Button("Delete", role: .destructive) {
                            if let uid = authVM.user?.id, let pending = listPendingDeletion {
                                Task { await deleteList(uid: uid, listID: pending.id) }
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
                    if let uid = authVM.user?.id, let movie = movies[safe: currentIndex] {
                        startListsListener(uid: uid, movie: movie)
                        Task { await loadSelections(uid: uid, movie: movie) }
                    }
                }
                .onDisappear {
                    listsListener?.remove()
                    listsListener = nil
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .task {
            if movies.isEmpty { loadMovies() }
            // Preload list selections for current movie if available
            if let uid = authVM.user?.id, let movie = movies[safe: currentIndex] {
                startListsListener(uid: uid, movie: movie)
                Task {
                    await loadSelections(uid: uid, movie: movie)
                    await fetchUserRatingForCurrent()
                }
            }
        }
        .onChange(of: kind) { _ in
            movies = []
            currentIndex = 0
            loadMoviesForCurrentKind()
            // After kind changes, attempt to refresh list selections for the first movie (if user exists)
            Task { @MainActor in
                if let uid = authVM.user?.id, let movie = movies[safe: currentIndex] {
                    startListsListener(uid: uid, movie: movie)
                    Task {
                        await loadSelections(uid: uid, movie: movie)
                        await fetchUserRatingForCurrent()
                    }
                } else {
                    selectedLists = []
                }
            }
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
    private func startListsListener(uid: String, movie: Movie) {
        let ref = Firestore.firestore()
            .collection("users")
            .document(uid)
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
            Task { await loadSelections(uid: uid, movie: movie) }
        }
    }

    private func loadSelections(uid: String, movie: Movie) async {
        let type = (movie.mediaType ?? "movie").lowercased()
        let db = Firestore.firestore()
        var newSelected: Set<String> = []
        for list in userLists {
            let itemRef = db.collection("users").document(uid)
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

    private func addNewList(uid: String, name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let db = Firestore.firestore()
        do {
            let ref = db.collection("users").document(uid).collection("lists").document()
            try await ref.setData([
                "name": trimmed,
                "createdAt": FieldValue.serverTimestamp()
            ])
        } catch {
            print("[Picker Lists] add error:", error.localizedDescription)
        }
    }

    private func saveSelections(uid: String, movie: Movie) async {
        let type = (movie.mediaType ?? "movie").lowercased()
        let db = Firestore.firestore()
        let key = "\(type):\(movie.id)"
        for list in userLists {
            let itemRef = db.collection("users").document(uid)
                .collection("lists").document(list.id)
                .collection("items").document(key)
            do {
                if selectedLists.contains(list.id) {
                    try await itemRef.setData([
                        "movieId": movie.id,
                        "type": type,
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
    
    private func deleteList(uid: String, listID: String) async {
        let db = Firestore.firestore()
        do {
            try await db.collection("users").document(uid).collection("lists").document(listID).delete()
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
    
    // Updated helper to fetch user rating for current movie
    private func fetchUserRatingForCurrent() async {
        guard let uid = authVM.user?.id, let movie = movies[safe: currentIndex] else { return }
        let type = (movie.mediaType ?? "movie").lowercased()
        let db = Firestore.firestore()
        let doc = db.collection("ratings")
            .document("\(type):\(movie.id)")
            .collection("userRatings")
            .document(uid)
        do {
            let snap = try await doc.getDocument()
            if let val = snap.data()? ["rating"] as? Double {
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

    // MARK: - Ratings helpers
    // Updated submitRating to use repository aggregate and print debug info
    private func submitRating(_ value: Double) async {
        guard let uid = authVM.user?.id, let movie = movies[safe: currentIndex] else { return }
        let type = (movie.mediaType ?? "movie").lowercased()
        let repo = RatingsRepository()
        do {
            let agg = try await repo.submitRating(uid: uid, movieID: movie.id, type: type, value: value)
            await MainActor.run {
                self.userPreviousRating = value
            }
            // Optionally log aggregate for debugging
            print("[Picker Rating] submit success -> count=", agg.count, " avg=", agg.average)
        } catch {
            print("[Picker Rating] submit failed:", error.localizedDescription)
        }
    }

    // Updated removeRating to use repository deletion and safe UI normalization
    private func removeRating() async {
        guard let uid = authVM.user?.id, let movie = movies[safe: currentIndex], let old = userPreviousRating else { return }
        let type = (movie.mediaType ?? "movie").lowercased()
        let repo = RatingsRepository()
        do {
            let agg = try await repo.deleteRating(uid: uid, movieID: movie.id, type: type, previousValue: old)
            await MainActor.run {
                self.userPreviousRating = nil
                self.tempRating = 0
            }
            print("[Picker Rating] remove success -> count=", agg.count, " avg=", agg.average)
        } catch {
            print("[Picker Rating] remove failed:", error.localizedDescription)
            await MainActor.run {
                self.userPreviousRating = nil
                self.tempRating = 0
            }
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
                    let pages = Array(1...10)
                    let results: [[Movie]] = try await withThrowingTaskGroup(of: [Movie].self, returning: [[Movie]].self) { group in
                        for p in pages {
                            group.addTask { try await MovieService().getTrending(page: p) }
                        }
                        var acc: [[Movie]] = []
                        for try await res in group { acc.append(res) }
                        return acc
                    }
                    var combined: [Movie] = results.flatMap { $0 }
                    var seen = Set<Int>()
                    combined = combined.filter { m in
                        if seen.contains(m.id) { return false }
                        seen.insert(m.id)
                        return true
                    }
                    combined.shuffle()
                    let filtered: [Movie]
                    if let uid = authVM.user?.id {
                        let disliked = await fetchRecentlyDislikedIDs(uid: uid)
                        filtered = combined.filter { !disliked.contains($0.id) }
                    } else {
                        filtered = combined
                    }
                    await MainActor.run {
                        self.movies = filtered
                    }
                case .tv:
                    let pages = Array(1...10)
                    let results: [[Movie]] = try await withThrowingTaskGroup(of: [Movie].self, returning: [[Movie]].self) { group in
                        for p in pages {
                            group.addTask { try await MovieService().getTrendingTV(page: p) }
                        }
                        var acc: [[Movie]] = []
                        for try await res in group { acc.append(res) }
                        return acc
                    }
                    var combined: [Movie] = results.flatMap { $0 }
                    var seen = Set<Int>()
                    combined = combined.filter { m in
                        if seen.contains(m.id) { return false }
                        seen.insert(m.id)
                        return true
                    }
                    combined.shuffle()
                    let filtered: [Movie]
                    if let uid = authVM.user?.id {
                        let disliked = await fetchRecentlyDislikedIDs(uid: uid)
                        filtered = combined.filter { !disliked.contains($0.id) }
                    } else {
                        filtered = combined
                    }
                    await MainActor.run {
                        self.movies = filtered
                    }
                }
                await MainActor.run {
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
                await MainActor.run {
                    if let uid = authVM.user?.id, let first = self.movies[safe: self.currentIndex] {
                        startListsListener(uid: uid, movie: first)
                        Task {
                            await loadSelections(uid: uid, movie: first)
                            await fetchUserRatingForCurrent()
                        }
                    } else {
                        self.selectedLists = []
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

