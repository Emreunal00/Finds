import Combine
import Observation
import SwiftUI

private final class SearchRatingsCache: ObservableObject {
    static let shared = SearchRatingsCache()
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

struct SearchView: View {
    @Binding var resetToken: Int

    @StateObject private var vm = SearchViewModel()
    @StateObject private var ratingsCache = SearchRatingsCache.shared
    @FocusState private var searchFocused: Bool
    @State private var hasSearched: Bool = false
    @State private var searchDebounceTimer: Timer?

    init(resetToken: Binding<Int> = .constant(0)) {
        self._resetToken = resetToken
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                searchControlsTop
                content
            }
            .padding(.horizontal)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if vm.genres.isEmpty {
                    await vm.loadGenres()
                }
            }
            .onChange(of: resetToken) { _ in
                // Aynı tab tekrar seçildiğinde Search başlangıç haline dönsün
                performFullReset()
            }
        }
    }

    // MARK: - Search controls
    private var searchControlsTop: some View {
        HStack(spacing: 10) {
            // Arama alanı (yanında ekstra arama butonu yok) + overlay ile "çarpı" butonu
            HStack(spacing: 12) {
                TextField("Search for a movie or TV show…", text: $vm.keyword)
                    .font(.system(size: 17)) // Yazı tipini büyüt
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .focused($searchFocused)
                    .onChange(of: vm.keyword) { newValue in
                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            hasSearched = false
                            searchDebounceTimer?.invalidate()
                            searchDebounceTimer = nil
                        } else {
                            searchDebounceTimer?.invalidate()
                            searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                                hasSearched = true
                                Task { await vm.search() }
                            }
                        }
                    }
                    .onSubmit {
                        hasSearched = true
                        Task { await vm.search() }
                    }
                    .overlay(alignment: .trailing) {
                        if showClearButton {
                            Button {
                                performFullReset()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .imageScale(.large) // ikon biraz büyüsün
                                    .padding(.trailing, 4)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear search and filters")
                        }
                    }
            }
            .padding(.horizontal, 16) // yatay padding artırıldı
            .padding(.vertical, 14)   // dikey padding artırıldı (yüksekliği büyütür)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous) // köşe yarıçapı artırıldı
                    .fill(Color(.secondarySystemBackground))
            )

            Spacer(minLength: 8)

            // Sağdaki filtre ikonları (YIL butonu sadece aramadan sonra görünür)
            if showYearFilterWhenSearched {
                HStack(spacing: 10) {
                    Menu {
                        Picker("Year", selection: $vm.selectedYear) {
                            Text("All").tag(Int?.none)
                            ForEach((1899...Calendar.current.component(.year, from: Date())).reversed(), id: \.self) { y in
                                Text(verbatim: String(y)).tag(Int?.some(y))
                            }
                        }
                    } label: {
                        Image(systemName: "calendar")
                            .imageScale(.large)
                            .font(.system(size: 22, weight: .regular)) // ikon biraz büyüsün
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                            .background(
                                Circle().fill(Color(.secondarySystemBackground))
                            )
                            .accessibilityLabel("Year")
                    }
                }
            }
        }
        .font(.footnote)
    }

    // Yıl filtresi ne zaman görünsün?
    private var showYearFilterWhenSearched: Bool {
        // Arama tetiklendiyse, ya da sonuç/hata oluştuysa veya bir genre seçildiyse göster
        hasSearched || !vm.results.isEmpty || vm.error != nil || vm.selectedGenreID != nil
    }

    // Clear butonunun görünmesi için koşul
    private var showClearButton: Bool {
        let hasKeyword = !vm.keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasKeyword || vm.selectedGenreID != nil || vm.selectedYear != nil || hasSearched || !vm.results.isEmpty || vm.error != nil
    }

    private func performFullReset() {
        vm.reset()
        searchDebounceTimer?.invalidate()
        searchDebounceTimer = nil
        vm.selectedGenreID = nil
        vm.selectedYear = nil
        hasSearched = false
        searchFocused = false
    }

    // MARK: - Content
    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            CustomLoadingView(message: "Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.error {
            VStack(spacing: 8) {
                Text("Failed")
                    .font(.headline)
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    Task {
                        if let gid = vm.selectedGenreID {
                            await vm.searchByGenre(genreID: gid)
                        } else if !vm.keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            await vm.search()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.results.isEmpty {
            genresGrid
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(vm.results) { movie in
                        NavigationLink {
                            MovieDetailView(movie: movie)
                        } label: {
                            HStack(spacing: 12) {
                                poster(for: movie)
                                    .frame(width: 70, height: 105)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(movie.title)
                                        .font(.headline)
                                    HStack(spacing: 8) {
                                        if movie.year > 0 {
                                            Text(String(movie.year))
                                        }
                                        if let avg = ratingsCache.average(for: movie) {
                                            Text(String(format: "%.1f / 5", avg))
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .onAppear { ratingsCache.loadIfNeeded(for: movie) }
                        Divider()
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Genres grid
    private var genresGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Genres")
                .font(.headline)

            let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(vm.genres) { genre in
                    Button {
                        vm.selectedGenreID = genre.id
                        hasSearched = true
                        Task { await vm.searchByGenre(genreID: genre.id) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "tag.fill")
                                .symbolRenderingMode(.hierarchical)
                            Text(genre.name)
                                .lineLimit(1)
                        }
                        .font(.footnote)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Poster helpers
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
            Image(movie.posterName)
                .resizable()
                .scaledToFill()
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Color(.tertiarySystemFill)
            Image(systemName: "film")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    SearchView(resetToken: .constant(0))
}
