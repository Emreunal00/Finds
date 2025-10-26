import SwiftUI

struct SearchView: View {
    @StateObject private var vm = SearchViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                searchControls
                content
            }
            .padding(.horizontal)
            .navigationTitle("Arama")
            .task {
                if vm.genres.isEmpty {
                    await vm.loadGenres()
                }
            }
        }
    }

    private var searchControls: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Film veya dizi ara…", text: $vm.keyword)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit {
                        Task { await vm.search() }
                    }
                Button {
                    Task { await vm.search() }
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.bordered)
            }

            HStack {
                Menu {
                    Picker("Tür", selection: $vm.selectedGenreID) {
                        Text("Tümü").tag(Int?.none)
                        ForEach(vm.genres) { g in
                            Text(g.name).tag(Int?.some(g.id))
                        }
                    }
                } label: {
                    Label(
                        vm.selectedGenreID.flatMap { id in vm.genres.first(where: { $0.id == id })?.name } ?? "Tür",
                        systemImage: "line.3.horizontal.decrease.circle"
                    )
                }

                Spacer()

                Menu {
                    Picker("Yıl", selection: $vm.selectedYear) {
                        Text("Tümü").tag(Int?.none)
                        ForEach((1950...Calendar.current.component(.year, from: Date())).reversed(), id: \.self) { y in
                            Text("\(y)").tag(Int?.some(y))
                        }
                    }
                } label: {
                    Label(vm.selectedYear.map(String.init) ?? "Yıl", systemImage: "calendar")
                }
            }
            .font(.footnote)
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView("Aranıyor…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.error {
            VStack(spacing: 8) {
                Text("Arama başarısız")
                    .font(.headline)
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Tekrar Dene") {
                    Task { await vm.search() }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.results.isEmpty {
            VStack(spacing: 8) {
                Text("Sonuç yok")
                    .font(.headline)
                Text("Bir anahtar kelime girip aramayı başlatın.")
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

