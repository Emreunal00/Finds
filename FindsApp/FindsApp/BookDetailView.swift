import SwiftUI
import FirebaseFirestore

struct BookDetailView: View {
    let book: Movie
    @EnvironmentObject var authVM: AuthViewModel

    @State private var userRating: Double = 0
    @State private var averageRating: Double = 0
    @State private var voteCount: Int = 0
    @State private var userPreviousRating: Double? = nil

    @State private var isShowingRatingSheet = false
    @State private var tempRating: Double = 0

    @State private var isShowingListsSheet = false
    @State private var newListName: String = ""
    @State private var userLists: [CustomUserList] = []
    @State private var selectedLists: Set<String> = []
    @State private var listsListener: ListenerRegistration? = nil
    @State private var listPendingDeletion: CustomUserList? = nil

    private var authorsText: String {
        (book.directors ?? []).joined(separator: ", ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                bookHeroSection
                actionRow
                metaSection

                if !book.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(book.summary)
                        .font(.body)
                        .foregroundStyle(.primary)
                }

                if !authorsText.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Author")
                            .font(.subheadline.weight(.semibold))
                        Text(authorsText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .background(
            LinearGradient(
                colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .sheet(isPresented: $isShowingRatingSheet) {
            ratingSheet
        }
        .sheet(isPresented: $isShowingListsSheet) {
            listsSheet
        }
        .task {
            await loadRatings()
        }
        .onAppear {
            if let uid = authVM.user?.id, let profileId = authVM.currentProfile?.id {
                startListsListener(uid: uid, profileId: profileId)
            }
        }
        .onDisappear {
            stopListsListener()
        }
    }

    private var isFavorite: Bool {
        guard let profile = authVM.currentProfile else { return false }
        return profile.favoritesEntries.contains { $0.id == book.id && $0.type.lowercased() == "book" }
    }

    private var isInWantToRead: Bool {
        guard let profile = authVM.currentProfile else { return false }
        return profile.booksWantToReadEntries.contains { $0.id == book.id && $0.type.lowercased() == "book" }
    }

    private var isRead: Bool {
        guard let profile = authVM.currentProfile else { return false }
        return profile.booksReadEntries.contains { $0.id == book.id && $0.type.lowercased() == "book" }
    }

    private var isRated: Bool {
        userPreviousRating != nil
    }

    private var primaryGenre: String {
        book.genres.first ?? "Book"
    }

    private var bookHeroSection: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(heroGradient)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: BookCatalog.symbolName(for: book))
                        .font(.system(size: 96, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.10))
                        .padding(.top, 18)
                        .padding(.trailing, 18)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                }

            HStack(alignment: .bottom, spacing: 18) {
                coverArtwork
                    .frame(width: 108, height: 162)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    }
                    .shadow(color: Color.black.opacity(0.22), radius: 14, x: 0, y: 8)

                VStack(alignment: .leading, spacing: 10) {
                    Text(primaryGenre.uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .lineLimit(1)

                    Text(book.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)

                    if !authorsText.isEmpty {
                        Text(authorsText)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.white.opacity(0.82))
                            .lineLimit(2)
                    }

                    HStack(spacing: 10) {
                        if book.year > 0 {
                            Label(String(book.year), systemImage: "calendar")
                        }

                        Label(String(format: "%.1f / 5", voteCount > 0 ? averageRating : 0), systemImage: "star.fill")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.84))

                    if voteCount > 0 {
                        Text("\(voteCount) vote")
                            .font(.caption2)
                            .foregroundStyle(Color.white.opacity(0.62))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 220)
    }

    @ViewBuilder
    private var coverArtwork: some View {
        if let coverURL = book.posterURL {
            AsyncImage(url: coverURL) { phase in
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
                    Color.white.opacity(0.28),
                    Color.white.opacity(0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 10) {
                Image(systemName: BookCatalog.symbolName(for: book))
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.78))

                Text(book.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .padding(.horizontal, 8)
            }
        }
    }

    private var heroGradient: LinearGradient {
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

    private var actionRow: some View {
        let columns = [
            GridItem(.flexible(minimum: 100), spacing: 12),
            GridItem(.flexible(minimum: 100), spacing: 12)
        ]

        return LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            Button {
                Task { await authVM.toggleFavorite(movieID: book.id, mediaType: "book", externalContentID: book.externalContentID) }
            } label: {
                Label("Favorite", systemImage: isFavorite ? "heart.fill" : "heart")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(isFavorite ? .pink : .secondary)

            Button {
                Task { await authVM.toggleWantToReadBook(movieID: book.id, externalContentID: book.externalContentID) }
            } label: {
                Label("Want to Read", systemImage: isInWantToRead ? "bookmark.fill" : "bookmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(isInWantToRead ? .blue : .secondary)

            Button {
                Task { await authVM.toggleReadBook(movieID: book.id, externalContentID: book.externalContentID) }
            } label: {
                Label("Read", systemImage: isRead ? "checkmark.circle.fill" : "checkmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(isRead ? .green : .secondary)

            Button {
                isShowingListsSheet = true
            } label: {
                Label(selectedLists.isEmpty ? "Add to List" : "In Lists", systemImage: selectedLists.isEmpty ? "text.badge.plus" : "text.badge.checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(selectedLists.isEmpty ? .secondary : .purple)

            Button {
                tempRating = userPreviousRating ?? userRating
                isShowingRatingSheet = true
            } label: {
                Label(isRated ? "Rated" : "Rate", systemImage: isRated ? "star.fill" : "star")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(isRated ? .yellow : .secondary)
        }
    }

    private var metaSection: some View {
        Group {
            if !book.genres.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(book.genres, id: \.self) { genre in
                            Text(genre)
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

    private var ratingSheet: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 20)
            Text(book.title)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(maxWidth: .infinity)
            Text("Rate this book")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            StarRatingView(rating: $tempRating, starSize: 48)
                .frame(height: 58)
            HStack(spacing: 12) {
                Button("Cancel") { isShowingRatingSheet = false }
                    .buttonStyle(.bordered)
                Button("Save") {
                    isShowingRatingSheet = false
                    Task {
                        await sendUserRating(tempRating)
                        await submitRating(tempRating)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                if isRated {
                    Button("Remove Rating", role: .destructive) {
                        isShowingRatingSheet = false
                        Task { await removeRating() }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding()
        .presentationDetents([.height(255), .medium])
    }

    private var listsSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Add to Lists").font(.title3.weight(.semibold))
                    Text("Select the lists to include this book. You can also create a new list.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.top, 16)

                Group {
                    if userLists.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "list.bullet.rectangle")
                                .font(.system(size: 28))
                                .foregroundStyle(.secondary)
                            Text("No lists yet").font(.headline)
                            Text("Create your first list below.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
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
                                        Text(list.name)
                                        Spacer()
                                        Button(role: .destructive) {
                                            listPendingDeletion = list
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 12)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if isSelected {
                                            selectedLists.remove(list.id)
                                        } else {
                                            selectedLists.insert(list.id)
                                        }
                                        if let uid = authVM.user?.id, let profileId = authVM.currentProfile?.id {
                                            Task { await saveSelections(uid: uid, profileId: profileId) }
                                        }
                                    }
                                    Divider().padding(.leading, 48)
                                }
                            }
                        }
                    }
                }

                HStack(spacing: 8) {
                    TextField("Create new list", text: $newListName)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        Task {
                            if let uid = authVM.user?.id, let profileId = authVM.currentProfile?.id {
                                await addNewList(uid: uid, profileId: profileId, name: newListName)
                            }
                            newListName = ""
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()

                HStack(spacing: 12) {
                    Button("Cancel") { isShowingListsSheet = false }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button("Save") {
                        Task {
                            if let uid = authVM.user?.id, let profileId = authVM.currentProfile?.id {
                                await saveSelections(uid: uid, profileId: profileId)
                            }
                            isShowingListsSheet = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(.ultraThinMaterial)
            }
            .navigationTitle("Lists")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Delete list?", isPresented: Binding(get: { listPendingDeletion != nil }, set: { if !$0 { listPendingDeletion = nil } })) {
                Button("Delete", role: .destructive) {
                    if let uid = authVM.user?.id, let profileId = authVM.currentProfile?.id, let pending = listPendingDeletion {
                        Task { await deleteList(uid: uid, profileId: profileId, listID: pending.id) }
                    }
                    listPendingDeletion = nil
                }
                Button("Cancel", role: .cancel) { listPendingDeletion = nil }
            } message: {
                Text("This action cannot be undone.")
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func loadRatings() async {
        do {
            if let agg = try await RatingsRepository().fetchAggregate(movieID: book.id, type: "book") {
                await MainActor.run {
                    voteCount = agg.count
                    averageRating = agg.average
                }
            }
            if let uid = authVM.user?.id,
               let rating = try await RatingsRepository().fetchUserRating(uid: uid, movieID: book.id, type: "book") {
                await MainActor.run {
                    userPreviousRating = rating
                    userRating = rating
                    tempRating = rating
                }
            }
        } catch {
            print("[Book Ratings] load failed:", error.localizedDescription)
        }
    }

    private func startListsListener(uid: String, profileId: String) {
        let ref = Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("profiles")
            .document(profileId)
            .collection("lists")
            .order(by: "createdAt", descending: false)
        listsListener = ref.addSnapshotListener { snapshot, error in
            if let error {
                print("[Book Lists] listener error:", error.localizedDescription)
                return
            }
            guard let docs = snapshot?.documents else { return }
            userLists = docs.map { doc in
                let name = doc.data()["name"] as? String ?? "Untitled"
                return CustomUserList(id: doc.documentID, name: name)
            }
            Task { await loadSelections(uid: uid, profileId: profileId) }
        }
    }

    private func stopListsListener() {
        listsListener?.remove()
        listsListener = nil
    }

    private func loadSelections(uid: String, profileId: String) async {
        let db = Firestore.firestore()
        var newSelected: Set<String> = []
        for list in userLists {
            let itemRef = db.collection("users").document(uid)
                .collection("profiles").document(profileId)
                .collection("lists").document(list.id)
                .collection("items").document("book:\(book.id)")
            do {
                let snap = try await itemRef.getDocument()
                if snap.exists {
                    newSelected.insert(list.id)
                }
            } catch {
                print("[Book Lists] load selection error:", error.localizedDescription)
            }
        }
        await MainActor.run {
            selectedLists = newSelected
        }
    }

    private func addNewList(uid: String, profileId: String, name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try await Firestore.firestore()
                .collection("users").document(uid)
                .collection("profiles").document(profileId)
                .collection("lists").document()
                .setData([
                    "name": trimmed,
                    "createdAt": FieldValue.serverTimestamp()
                ])
        } catch {
            print("[Book Lists] add error:", error.localizedDescription)
        }
    }

    private func saveSelections(uid: String, profileId: String) async {
        let db = Firestore.firestore()
        let key = "book:\(book.id)"
        for list in userLists {
            let itemRef = db.collection("users").document(uid)
                .collection("profiles").document(profileId)
                .collection("lists").document(list.id)
                .collection("items").document(key)
            do {
                if selectedLists.contains(list.id) {
                    try await itemRef.setData([
                        "movieId": book.id,
                        "type": "book",
                        "externalContentID": book.externalContentID as Any,
                        "addedAt": FieldValue.serverTimestamp()
                    ])
                } else {
                    try await itemRef.delete()
                }
            } catch {
                print("[Book Lists] save error:", error.localizedDescription)
            }
        }
    }

    private func deleteList(uid: String, profileId: String, listID: String) async {
        do {
            try await Firestore.firestore()
                .collection("users").document(uid)
                .collection("profiles").document(profileId)
                .collection("lists").document(listID)
                .delete()
            await MainActor.run {
                selectedLists.remove(listID)
            }
        } catch {
            print("[Book Lists] delete error:", error.localizedDescription)
        }
    }

    private func submitRating(_ value: Double) async {
        guard let uid = authVM.user?.id else { return }
        do {
            let agg = try await RatingsRepository().submitRating(uid: uid, movieID: book.id, type: "book", value: value)
            await MainActor.run {
                voteCount = agg.count
                averageRating = agg.average
                userPreviousRating = value
                userRating = value
            }
        } catch {
            print("[Book Ratings] submit failed:", error.localizedDescription)
        }
    }

    private func removeRating() async {
        guard let uid = authVM.user?.id, let old = userPreviousRating else { return }
        do {
            let agg = try await RatingsRepository().deleteRating(uid: uid, movieID: book.id, type: "book", previousValue: old)
            await MainActor.run {
                voteCount = agg.count
                averageRating = agg.average
                userPreviousRating = nil
                userRating = 0
                tempRating = 0
            }
        } catch {
            print("[Book Ratings] remove failed:", error.localizedDescription)
        }
    }

    private func sendUserRating(_ value: Double) async {
        await MainActor.run {
            var currentTotal = averageRating * Double(voteCount)
            var currentCount = voteCount

            if let old = userPreviousRating {
                currentTotal += (value - old)
                averageRating = currentCount > 0 ? currentTotal / Double(currentCount) : 0
                let _ = RatingsStore.applyDelta(for: book.id, type: "book", add: value - old, incrementCount: false)
            } else {
                currentTotal += value
                currentCount += 1
                averageRating = currentTotal / Double(currentCount)
                voteCount = currentCount
                let _ = RatingsStore.applyDelta(for: book.id, type: "book", add: value, incrementCount: true)
            }

            if let userID = authVM.user?.id {
                RatingsStore.setRating(value, for: userID, movieID: book.id, type: "book")
            }

            userPreviousRating = value
            userRating = value
        }
    }
}
