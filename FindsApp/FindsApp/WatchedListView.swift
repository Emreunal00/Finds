import SwiftUI

struct WatchedListView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var movies: [Movie] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    private let service: MovieServicing = MovieService()

    private var entries: [WatchedEntry] {
        guard let u = authVM.user else { return [] }
        if !u.watchedEntries.isEmpty {
            return u.watchedEntries
        } else {
            return u.watchedIDs.map { WatchedEntry(id: $0, type: "movie") }
        }
    }

    var body: some View {
        List {
            if isLoading {
                HStack { Spacer(); ProgressView("Loading…"); Spacer() }
            } else if let err = errorMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Failed to load").font(.headline)
                    Text(err).font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                ForEach(movies) { movie in
                    NavigationLink { MovieDetailView(movie: movie) } label: {
                        HStack(spacing: 12) {
                            poster(for: movie)
                                .frame(width: 50, height: 75)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(movie.title).font(.headline)
                                HStack(spacing: 8) {
                                    if movie.year > 0 { Text(String(movie.year)) }
                                    if movie.rating > 0 {
                                        let percent = Int(round(movie.rating * 20))
                                        Text("\(percent)%").foregroundStyle(ScoreColor.color(for: percent))
                                    }
                                }
                                .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
        .navigationTitle("All Watched")
        .task { await loadAll() }
        .onChange(of: authVM.listsVersion) { _ in Task { await loadAll() } }
    }

    private func loadAll() async {
        let es = entries
        guard !es.isEmpty else {
            movies = []
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let fetched: [Movie] = try await withThrowingTaskGroup(of: (Int, Movie?).self) { group in
                for entry in es {
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
                let ordered = es.compactMap { map[$0.id] ?? nil }
                return ordered.compactMap { $0 }
            }
            movies = fetched
        } catch {
            errorMessage = error.localizedDescription
            movies = []
        }
    }

    @ViewBuilder
    private func poster(for movie: Movie) -> some View {
        if let url = movie.posterURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty: ZStack { Color(.tertiarySystemFill); ProgressView() }
                case .success(let image): image.resizable().scaledToFill()
                case .failure: placeholder
                @unknown default: placeholder
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
}
