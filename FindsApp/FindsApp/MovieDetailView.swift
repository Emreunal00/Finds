import SwiftUI
import FirebaseFirestore

struct CustomUserList: Identifiable, Equatable {
    let id: String
    let name: String
}

struct StarRatingView: View {
    @Binding var rating: Double // 0.0–5.0 (yarım yıldız dahil)
    let starSize: CGFloat
    let maxRating: Int = 5
    var onRatingChanged: ((Double) -> Void)? = nil

    init(rating: Binding<Double>, starSize: CGFloat = 100, onRatingChanged: ((Double) -> Void)? = nil) {
        self._rating = rating
        self.starSize = starSize
        self.onRatingChanged = onRatingChanged
    }

    @GestureState private var dragLocation: CGPoint = .zero

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(0..<maxRating, id: \.self) { idx in
                    star(for: idx)
                        .frame(width: starSize, height: starSize)
                        .padding(.horizontal, -starSize * 0.08)
                }
            }
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, alignment: .center)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let widthPerStar = geo.size.width / CGFloat(maxRating)
                    let position = min(max(value.location.x, 0), geo.size.width)
                    let raw = position / widthPerStar
                    let stepped = (raw * 2).rounded() / 2 // round to nearest 0.5
                    let newRating = min(max(stepped, 0), Double(maxRating))
                    if rating != newRating {
                        rating = newRating
                        onRatingChanged?(newRating)
                    }
                }
            )
        }
        .frame(height: starSize)
    }

    @ViewBuilder
    private func star(for idx: Int) -> some View {
        let full = Double(idx + 1)
        if rating >= full {
            Image(systemName: "star.fill").foregroundStyle(.yellow)
        } else if rating >= full - 0.5 {
            Image(systemName: "star.leadinghalf.filled").foregroundStyle(.yellow)
        } else {
            Image(systemName: "star").foregroundStyle(.gray)
        }
    }
}

struct MovieDetailView: View {
    let movie: Movie
    @EnvironmentObject var authVM: AuthViewModel

    @State private var userRating: Double = 0.0
    @State private var averageRating: Double = 0.0
    @State private var voteCount: Int = 0
    @State private var userPreviousRating: Double? = nil

    @State private var isShowingRatingSheet: Bool = false
    @State private var tempRating: Double = 0.0

    @State private var isShowingListsSheet: Bool = false
    @State private var newListName: String = ""
    @State private var userLists: [CustomUserList] = []
    @State private var selectedLists: Set<String> = []
    @State private var listsListener: ListenerRegistration? = nil

    @State private var castNames: [String] = []
    @State private var createdByNames: [String] = []
    @State private var isCastExpanded: Bool = false

    @State private var directorName: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerPoster
                titleSection

                actionRow

                metaSection

                if !movie.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(movie.summary)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .padding(.top, 4)
                }

                // Credits (Created by, Directors & Cast)
                if !(createdByNames.isEmpty && directorName == nil && castNames.isEmpty) {
                    VStack(alignment: .leading, spacing: 8) {
                        // Created by (TV only)
                        if !createdByNames.isEmpty {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("Created by:").font(.subheadline.weight(.semibold))
                                Text(createdByNames.joined(separator: ", "))
                                    .font(.subheadline)
                            }
                        }
                        // Director(s)
                        if let directorName {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("Director:").font(.subheadline.weight(.semibold))
                                Text(directorName).font(.subheadline)
                            }
                        }
                        // Cast with expand/collapse
                        if !castNames.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Cast:").font(.subheadline.weight(.semibold))
                                let maxToShow = isCastExpanded ? castNames.count : min(10, castNames.count)
                                Text(Array(castNames.prefix(maxToShow)).joined(separator: ", "))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(isCastExpanded ? nil : 3)
                                if castNames.count > 10 {
                                    Button(isCastExpanded ? "Show less" : "Show more") {
                                        withAnimation { isCastExpanded.toggle() }
                                    }
                                    .font(.footnote.weight(.semibold))
                                }
                            }
                        }
                    }
                    .padding(.top, 6)
                }

                Spacer(minLength: 12)
            }
            .padding()
        }
        .navigationTitle(movie.title)
        .navigationBarTitleDisplayMode(.inline)
        .background(
            LinearGradient(
                colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                startPoint: .top,
                endPoint: .bottom
            ).ignoresSafeArea()
        )
        .sheet(isPresented: $isShowingRatingSheet) {
            VStack(spacing: 16) {
                Text("Rate \(movie.title)").font(.headline)
                StarRatingView(rating: $tempRating, starSize: 80) { newValue in
                    // live preview inside sheet
                }
                .frame(height: 110)
                HStack(spacing: 12) {
                    Button("Cancel") { isShowingRatingSheet = false }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .font(.headline)
                    Button("Save") {
                        isShowingRatingSheet = false
                        Task {
                            await sendUserRating(tempRating) // optimistic local update
                            await submitRating(tempRating)    // persist to backend
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.large)
                    .font(.headline)

                    if isRated {
                        Button(role: .destructive) {
                            isShowingRatingSheet = false
                            Task { await removeRating() }
                        } label: {
                            Text("Remove Rating")
                        }
                        .controlSize(.large)
                        .font(.headline)
                    }
                }
                .padding(.top, 8)
                Spacer(minLength: 0)
            }
            .padding()
            .presentationDetents([.height(240), .medium])
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

                    // Search
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search lists", text: Binding(
                            get: { "" },
                            set: { _ in }
                        ))
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
                                                if let uid = authVM.user?.id {
                                                    Task { await deleteList(uid: uid, listID: list.id) }
                                                }
                                            } label: {
                                                Text("Delete")
                                            }
                                        }
                                        .contentShape(Rectangle())
                                        .padding(.horizontal)
                                        .padding(.vertical, 12)
                                        .background(
                                            Rectangle().fill(Color(.secondarySystemBackground)).opacity(0.001)
                                        )
                                        .onTapGesture {
                                            if selectedLists.contains(list.id) {
                                                selectedLists.remove(list.id)
                                            } else {
                                                selectedLists.insert(list.id)
                                            }
                                            if let uid = authVM.user?.id {
                                                Task { await saveSelections(uid: uid) }
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
                                if let uid = authVM.user?.id { await saveSelections(uid: uid) }
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
                .onAppear { if let uid = authVM.user?.id { startListsListener(uid: uid) } }
                .onDisappear { stopListsListener() }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            if let uid = authVM.user?.id {
                startListsListener(uid: uid)
            }
        }
        .onDisappear {
            stopListsListener()
        }
        .task {
            let service: MovieServicing = MovieService()
            let type = (movie.mediaType ?? "movie").lowercased()
            print("[Ratings] .task load for key:", "\(type):\(movie.id)")
            do {
                if let agg = try await RatingsRepository().fetchAggregate(movieID: movie.id, type: type) {
                    print("[Ratings] fetched aggregate -> count=", agg.count, "avg=", agg.average)
                    await MainActor.run {
                        self.voteCount = agg.count
                        self.averageRating = agg.average
                    }
                } else {
                    print("[Ratings] no aggregate found, fallback to movie.rating")
                    await MainActor.run {
                        self.voteCount = 0
                        self.averageRating = 0
                    }
                }
                if let uid = authVM.user?.id {
                    if let ur = try await RatingsRepository().fetchUserRating(uid: uid, movieID: movie.id, type: type) {
                        print("[Ratings] fetched user rating for uid=", uid, "->", ur)
                        await MainActor.run {
                            self.userPreviousRating = ur
                            self.userRating = ur
                            self.tempRating = ur
                        }
                    } else {
                        print("[Ratings] no user rating for uid=", uid)
                    }
                } else {
                    print("[Ratings] no auth user, skipping user rating fetch")
                }
            } catch {
                print("[Ratings] load failed:", error.localizedDescription)
            }

            await loadCredits()
        }
    }

    private var isFavorite: Bool {
        guard let profile = authVM.user else { return false }
        let type = (movie.mediaType ?? "movie").lowercased()
        return profile.favoritesEntries.contains { $0.id == movie.id && $0.type.lowercased() == type }
    }

    private var isInWatchlist: Bool {
        guard let profile = authVM.user else { return false }
        let type = (movie.mediaType ?? "movie").lowercased()
        return profile.watchlistEntries.contains { $0.id == movie.id && $0.type.lowercased() == type }
    }

    private var isWatched: Bool {
        guard let profile = authVM.user else { return false }
        let type = (movie.mediaType ?? "movie").lowercased()
        return profile.watchedEntries.contains { $0.id == movie.id && $0.type.lowercased() == type }
    }
    
    private var isRated: Bool {
        return userPreviousRating != nil
    }
    
    private var isInAnyCustomList: Bool {
        !selectedLists.isEmpty
    }

    private var headerPoster: some View {
        Group {
            if let url = movie.posterURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ZStack { Color(.tertiarySystemFill); ProgressView() }
                    case .success(let image):
                        image.resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
                .frame(maxWidth: .infinity)
            } else if !movie.posterName.isEmpty {
                Image(movie.posterName)
                    .resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                placeholder
            }
        }
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(movie.title).font(.title2).bold()
            HStack(spacing: 8) {
                if movie.year > 0 { Text(String(movie.year)) }
                if let runtime = movie.durationMinutes {
                    Label("\(runtime) min", systemImage: "clock").symbolRenderingMode(.hierarchical)
                }
                // Rating and vote count combined in one string; show 0 when no votes
                let displayAverage = voteCount > 0 ? averageRating : 0
                Text(String(format: "%.1f / 5 (\(voteCount) vote)", displayAverage))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var actionRow: some View {
        let columns = [
            GridItem(.flexible(minimum: 100), spacing: 12),
            GridItem(.flexible(minimum: 100), spacing: 12)
        ]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            Button {
                let type = movie.mediaType ?? "movie"
                Task { await authVM.toggleFavorite(movieID: movie.id, mediaType: type) }
            } label: {
                Label(isFavorite ? "Favorite" : "Favorite",
                      systemImage: isFavorite ? "heart.fill" : "heart")
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(isFavorite ? .pink : .secondary)
            .disabled(authVM.user == nil)

            Button {
                let type = movie.mediaType ?? "movie"
                Task { await authVM.toggleWatchlist(movieID: movie.id, mediaType: type) }
            } label: {
                Label(isInWatchlist ? "Watchlist" : "Watchlist",
                      systemImage: isInWatchlist ? "bookmark.fill" : "bookmark")
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(isInWatchlist ? .blue : .secondary)
            .disabled(authVM.user == nil)

            Button {
                let type = movie.mediaType ?? "movie"
                Task { await authVM.toggleWatched(movieID: movie.id, type: type) }
            } label: {
                Label(isWatched ? "Watched" : "Watched",
                      systemImage: isWatched ? "checkmark.circle.fill" : "checkmark.circle")
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(isWatched ? .green : .secondary)
            .disabled(authVM.user == nil)

            Button {
                isShowingListsSheet = true
            } label: {
                Label(isInAnyCustomList ? "In Lists" : "Add to List",
                      systemImage: isInAnyCustomList ? "text.badge.checkmark" : "text.badge.plus")
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(isInAnyCustomList ? .purple : .secondary)
            .disabled(authVM.user == nil)

            Button {
                tempRating = userPreviousRating ?? userRating
                isShowingRatingSheet = true
            } label: {
                Label(isRated ? "Rated" : "Rate",
                      systemImage: isRated ? "star.fill" : "star")
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(isRated ? .yellow : .secondary)
            .disabled(authVM.user == nil)
        }
        .font(.subheadline)
        .padding(.top, 4)
    }

    private var metaSection: some View {
        let readableGenres: [String] = movie.genres.map { token in
            if token.hasPrefix("#"), let id = Int(token.dropFirst()) { return "#\(id)" }
            return token
        }
        return Group {
            if !readableGenres.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(readableGenres, id: \.self) { g in
                            Text(g)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            Color(.tertiarySystemFill)
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Image(systemName: "film").font(.system(size: 40)).foregroundStyle(.secondary)
        }
    }

    private func startListsListener(uid: String) {
        let ref = Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("lists")
            .order(by: "createdAt", descending: false)
        listsListener = ref.addSnapshotListener { snapshot, error in
            if let error = error {
                print("[Lists] listener error:", error.localizedDescription)
                return
            }
            guard let docs = snapshot?.documents else { return }
            let lists = docs.map { doc -> CustomUserList in
                let name = doc.data()["name"] as? String ?? "Untitled"
                return CustomUserList(id: doc.documentID, name: name)
            }
            self.userLists = lists
            // Preload selections for this movie in user's lists
            Task { await loadSelections(uid: uid) }
        }
    }

    private func stopListsListener() {
        listsListener?.remove()
        listsListener = nil
    }

    private func loadSelections(uid: String) async {
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
                print("[Lists] load selection error for \(list.id):", error.localizedDescription)
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
            print("[Lists] add error:", error.localizedDescription)
        }
    }

    private func saveSelections(uid: String) async {
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
                print("[Lists] save item error for \(list.id):", error.localizedDescription)
            }
        }
    }

    private func deleteList(uid: String, listID: String) async {
        let db = Firestore.firestore()
        do {
            try await db.collection("users").document(uid).collection("lists").document(listID).delete()
            await MainActor.run { self.selectedLists.remove(listID) }
        } catch {
            print("[Lists] delete error for list=\(listID):", error.localizedDescription)
        }
    }

    private func submitRating(_ value: Double) async {
        guard let uid = authVM.user?.id else {
            print("[Ratings] submit aborted: no auth user")
            return
        }
        let type = (movie.mediaType ?? "movie").lowercased()
        print("[Ratings] submit start uid=", uid, " key=", "\(type):\(movie.id)", " value=", value)
        let repo = RatingsRepository()
        do {
            let agg = try await repo.submitRating(uid: uid, movieID: movie.id, type: type, value: value)
            print("[Ratings] submit success -> count=", agg.count, " avg=", agg.average)
            await MainActor.run {
                self.voteCount = agg.count
                self.averageRating = agg.average
                self.userPreviousRating = value
                self.userRating = value
            }
        } catch {
            print("[Ratings] submit failed:", error.localizedDescription)
        }
    }

    private func removeRating() async {
        guard let uid = authVM.user?.id else {
            print("[Ratings] remove aborted: no auth user")
            return
        }
        let type = (movie.mediaType ?? "movie").lowercased()
        print("[Ratings] remove start uid=", uid, " key=", "\(type):\(movie.id)")
        let repo = RatingsRepository()
        do {
            if let old = self.userPreviousRating {
                // Try repository deletion and receive updated aggregate
                let agg = try await repo.deleteRating(uid: uid, movieID: movie.id, type: type, previousValue: old)
                print("[Ratings] remove success -> count=", agg.count, " avg=", agg.average)
                await MainActor.run {
                    self.voteCount = agg.count
                    self.averageRating = agg.average
                    self.userPreviousRating = nil
                    self.userRating = 0
                    self.tempRating = 0
                }
            } else {
                // No previous rating: just normalize UI
                await MainActor.run {
                    self.userPreviousRating = nil
                    self.userRating = 0
                    self.tempRating = 0
                }
            }
        } catch {
            print("[Ratings] remove failed:", error.localizedDescription)
            // Fallback: adjust local aggregates if we know old value
            if let old = self.userPreviousRating {
                await MainActor.run {
                    var currentTotal = averageRating * Double(voteCount)
                    var currentCount = voteCount
                    currentTotal -= old
                    currentCount = max(0, currentCount - 1)
                    averageRating = currentCount > 0 ? currentTotal / Double(currentCount) : 0
                    voteCount = currentCount
                    self.userPreviousRating = nil
                    self.userRating = 0
                    self.tempRating = 0
                }
            }
        }
    }

    private func sendUserRating(_ value: Double) async {
        await MainActor.run {
            let type = (movie.mediaType ?? "movie").lowercased()

            // Mevcut toplu veriyi oku
            var currentTotal = averageRating * Double(voteCount)
            var currentCount = voteCount

            if let old = userPreviousRating {
                // Güncelleme: toplamı yeni - eski farkı kadar ayarla, oy sayısı değişmez
                currentTotal += (value - old)
                // Local UI güncelle
                averageRating = currentCount > 0 ? currentTotal / Double(currentCount) : 0
                // Kalıcı aggregate güncellemesi
                let _ = RatingsStore.applyDelta(for: movie.id, type: type, add: (value - old), incrementCount: false)
            } else {
                // İlk oy: toplamı artır, oy sayısını yükselt
                currentTotal += value
                currentCount += 1
                averageRating = currentTotal / Double(currentCount)
                voteCount = currentCount
                // Kalıcı aggregate güncellemesi
                let _ = RatingsStore.applyDelta(for: movie.id, type: type, add: value, incrementCount: true)
            }

            // Kullanıcıya özel puanı güncelle ve sakla
            if let userID = authVM.user?.id {
                RatingsStore.setRating(value, for: userID, movieID: movie.id, type: type)
            }

            userPreviousRating = value
            userRating = value
        }
    }

    private func loadCredits() async {
        let service: MovieServicing = MovieService()
        let type = (movie.mediaType ?? "movie").lowercased()
        do {
            if type == "movie" {
                let credits = try await service.fetchMovieCredits(id: movie.id)
                // Directors (there can be multiple)
                let directors = credits.crew.filter { ($0.job ?? "").lowercased() == "director" }.map { $0.name }
                let directorJoined = directors.joined(separator: ", ")
                let topCast = credits.cast.map { $0.name }
                await MainActor.run {
                    self.directorName = directorJoined.isEmpty ? nil : directorJoined
                    self.castNames = topCast
                    self.createdByNames = []
                }
            } else {
                async let creditsTask = service.fetchTVCredits(id: movie.id)
                async let detailTask = service.fetchTVDetail(id: movie.id)
                let (credits, detail) = try await (creditsTask, detailTask)
                let directorLike = credits.crew.filter { ($0.job ?? "").lowercased().contains("director") }.map { $0.name }
                let directorJoined = directorLike.joined(separator: ", ")
                let topCast = credits.cast.map { $0.name }
                let creators = (detail.createdBy ?? []).map { $0.name }
                await MainActor.run {
                    self.directorName = directorJoined.isEmpty ? nil : directorJoined
                    self.castNames = topCast
                    self.createdByNames = creators
                }
            }
        } catch {
            await MainActor.run {
                // leave existing values or clear gracefully
                if self.directorName == nil { self.directorName = nil }
                if self.castNames.isEmpty { self.castNames = [] }
                if self.createdByNames.isEmpty { self.createdByNames = [] }
            }
        }
    }
}

#Preview {
    let sample = Movie(
        id: 1,
        title: "Sample Movie",
        year: 2023,
        genres: ["#28", "#12"],
        posterName: "",
        rating: 4.2,
        summary: "This is a sample overview for the movie. It provides a brief description of the plot.",
        posterURL: URL(string: "https://image.tmdb.org/t/p/w500/abc123.jpg"),
        durationMinutes: 123,
        mediaType: "movie"
    )
    return NavigationStack {
        MovieDetailView(movie: sample)
            .environmentObject(AuthViewModel())
    }
}
