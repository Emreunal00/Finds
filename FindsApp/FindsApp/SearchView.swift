import SwiftUI

struct SearchView: View {
    @StateObject private var vm = SearchViewModel()
    @FocusState private var searchFocused: Bool
    @State private var hasSearched: Bool = false

    // Basit öneri kümesi (istersen ViewModel’e taşıyabilir veya sunucudan çekebilirsin)
    private let suggestions: [String] = [
        "Popular this week",
        "Top rated",
        "Sci‑Fi",
        "Comedy",
        "Action",
        "Drama",
        "Oscar winners",
        "Family",
        "2024 releases",
        "Classic movies"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                searchControlsTop
                content
            }
            .padding(.horizontal)
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if vm.genres.isEmpty {
                    await vm.loadGenres()
                }
            }
        }
    }

    // MARK: - Search controls (always at top with Genre/Year)
    private var searchControlsTop: some View {
        HStack(spacing: 8) {
            // Left: search field + search button
            HStack(spacing: 10) {
                TextField("Search for a movie or TV show…", text: $vm.keyword)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .focused($searchFocused)
                    .onChange(of: vm.keyword) { newValue in
                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            hasSearched = false
                        }
                    }
                    .onSubmit {
                        hasSearched = true
                        Task { await vm.search() }
                    }

                Button {
                    hasSearched = true
                    Task { await vm.search() }
                } label: {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .imageScale(.large)
                        .font(.system(size: 22, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .accessibilityLabel("Search")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )

            Spacer(minLength: 8)

            // Right: Genre and Year icon buttons
            HStack(spacing: 10) {
                Menu {
                    Picker("Genre", selection: $vm.selectedGenreID) {
                        Text("All").tag(Int?.none)
                        ForEach(vm.genres) { g in
                            Text(g.name).tag(Int?.some(g.id))
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .imageScale(.large)
                        .font(.system(size: 20, weight: .regular))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 6)
                        .background(
                            Circle().fill(Color(.secondarySystemBackground))
                        )
                        .accessibilityLabel("Genre")
                }

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
                        .font(.system(size: 20, weight: .regular))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 6)
                        .background(
                            Circle().fill(Color(.secondarySystemBackground))
                        )
                        .accessibilityLabel("Year")
                }
            }
        }
        .font(.footnote)
    }

    // MARK: - Content
    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView("Searching…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !hasSearched {
            // Arama yapılmadan önce: öneriler
            suggestionsView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if let err = vm.error {
            VStack(spacing: 8) {
                Text("Search failed")
                    .font(.headline)
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    Task { await vm.search() }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.results.isEmpty {
            VStack(spacing: 8) {
                Text("No results")
                    .font(.headline)
                Text("Try another keyword or adjust filters.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                                        if movie.rating > 0 {
                                            let percent = Int(round(movie.rating * 20))
                                            Text("\(percent)%")
                                                .foregroundStyle(ScoreColor.color(for: percent))
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Suggestions
    private var suggestionsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Suggestions")
                .font(.headline)

            // Basit chip düzeni
            let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(suggestions, id: \.self) { s in
                    Button {
                        // Öneriye tıklanınca arama yap
                        vm.keyword = s
                        hasSearched = true
                        Task { await vm.search() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .symbolRenderingMode(.hierarchical)
                            Text(s)
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
                    ZStack {
                        Color(.tertiarySystemFill)
                        ProgressView()
                    }
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
    SearchView()
}
