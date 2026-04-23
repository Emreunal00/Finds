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
                headerCover
                titleSection
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

    private var isInWatchlist: Bool {
        guard let profile = authVM.currentProfile else { return false }
        return profile.watchlistEntries.contains { $0.id == book.id && $0.type.lowercased() == "book" }
    }

    private var isWatched: Bool {
        guard let profile = authVM.currentProfile else { return false }
        return profile.watchedEntries.contains { $0.id == book.id && $0.type.lowercased() == "book" }
    }

    private var isRated: Bool {
        userPreviousRating != nil
    }

    private var headerCover: some View {
        Group {
            if let coverURL = book.posterURL {
                AsyncImage(url: coverURL) { phase in
                    switch phase {
                    case .empty:
                        coverPlaceholder
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    case .failure:
                        coverPlaceholder
                    @unknown default:
                        coverPlaceholder
                    }
                }
                .frame(maxWidth: .infinity)
            } else if !book.posterName.isEmpty {
                Image(book.posterName)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                coverPlaceholder
            }
        }
    }

    private var coverPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color.orange.opacity(0.22), Color.yellow.opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 14) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.yellow)
                Text(book.title)
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                mediaTypeBadge
                Text(book.title)
                    .font(.title2.bold())
            }
            HStack(spacing: 8) {
                if book.year > 0 {
                    Text(String(book.year))
                }
                Text(String(format: "%.1f / 5 (%d vote)", voteCount > 0 ? averageRating : 0, voteCount))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private var mediaTypeBadge: some View {
        Image(systemName: "book.closed.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
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
                Task { await authVM.toggleWatchlist(movieID: book.id, mediaType: "book", externalContentID: book.externalContentID) }
            } label: {
                Label("Want to Read", systemImage: isInWatchlist ? "bookmark.fill" : "bookmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(isInWatchlist ? .blue : .secondary)

            Button {
                Task { await authVM.toggleWatched(movieID: book.id, type: "book", externalContentID: book.externalContentID) }
            } label: {
                Label("Read", systemImage: isWatched ? "checkmark.circle.fill" : "checkmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(isWatched ? .green : .secondary)

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
