import SwiftUI
import FirebaseFirestore

struct CustomListDetailView: View {
    let list: ProfileCustomUserList
    @EnvironmentObject var authVM: AuthViewModel

    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var movies: [Movie] = []
    private let service: MovieServicing = MovieService()

    var body: some View {
        Group {
            if isLoading {
                VStack { ProgressView("Loading…") }.frame(maxWidth: .infinity)
            } else if let err = errorMessage {
                VStack(spacing: 8) {
                    Text("Failed to load").font(.headline)
                    Text(err).font(.footnote).foregroundStyle(.secondary)
                    Button("Retry") { Task { await loadItems() } }.buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
            } else if movies.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "text.badge.plus").font(.system(size: 28)).foregroundStyle(.secondary)
                    Text("No items in this list").font(.headline)
                    Text("Use 'Add to List' in a movie to include it here.").font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(movies) { movie in
                        NavigationLink { MovieDetailView(movie: movie) } label: {
                            row(for: movie)
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable { await loadItems() }
            }
        }
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadItems() }
    }

    private func row(for movie: Movie) -> some View {
        HStack(spacing: 12) {
            poster(for: movie)
                .frame(width: 60, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(movie.title).font(.headline)
                HStack(spacing: 8) {
                    if movie.year > 0 { Text(String(movie.year)) }
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
        .padding(.vertical, 6)
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
            Image(systemName: "film").font(.system(size: 16)).foregroundStyle(.secondary)
        }
    }

    private func loadItems() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        guard let uid = authVM.user?.id else {
            errorMessage = "Not signed in"
            movies = []
            return
        }

        do {
            let db = Firestore.firestore()
            let itemsRef = db.collection("users").document(uid)
                .collection("lists").document(list.id)
                .collection("items")
                .order(by: "addedAt", descending: true)

            let snap = try await itemsRef.getDocuments()
            let items = snap.documents.compactMap { doc -> (Int, String)? in
                let data = doc.data()
                guard let id = data["movieId"] as? Int, let type = data["type"] as? String else { return nil }
                return (id, type)
            }

            let fetched: [Movie] = await withTaskGroup(of: (Int, Movie?).self) { group -> [Movie] in
                for (id, type) in items {
                    group.addTask {
                        do {
                            if type.lowercased() == "movie" {
                                let m = try await service.fetchMovieBasic(id: id)
                                return (id, m)
                            } else {
                                let tv = try await service.fetchTVBasic(id: id)
                                return (id, tv)
                            }
                        } catch {
                            return (id, nil)
                        }
                    }
                }
                var results: [(Int, Movie?)] = []
                while let next = await group.next() { results.append(next) }
                let map = Dictionary(uniqueKeysWithValues: results)
                let ordered = items.compactMap { map[$0.0] ?? nil }
                return ordered.compactMap { $0 }
            }
            movies = fetched
        } catch {
            errorMessage = error.localizedDescription
            movies = []
        }
    }
}

#Preview {
    NavigationStack {
        CustomListDetailView(list: ProfileCustomUserList(id: "abc", name: "My List"))
            .environmentObject(AuthViewModel())
    }
}
