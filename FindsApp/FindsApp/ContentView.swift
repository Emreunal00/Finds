import SwiftUI

// MARK: - Models

struct Movie: Identifiable, Hashable {
    let id: UUID = UUID()
    let title: String
    let year: Int
    let genres: [String]
    let posterName: String // legacy
    let rating: Double     // 0...5
    let summary: String
    let posterURL: URL?    // NEW: TMDb poster URL
    var durationMinutes: Int? // NEW: runtime
}

struct Review: Identifiable {
    let id = UUID()
    let userName: String
    let text: String
    let stars: Int
}

// MARK: - Mock Data (kept for reviews and genre names if needed)

enum MockData {
    static let reviews: [Review] = [
        Review(userName: "Aylin", text: "Görsel anlatımı çok güçlü, müzikler harika.", stars: 5),
        Review(userName: "Mert", text: "Senaryo biraz tahmin edilebilir ama keyifli.", stars: 4),
        Review(userName: "Deniz", text: "Bazı sahneler uzundu, yine de izlenir.", stars: 3)
    ]

    static let allGenres = ["Action", "Adventure", "Animation", "Comedy", "Crime", "Drama", "Fantasy", "Horror", "Romance", "Sci-Fi", "Thriller", "Cyberpunk"]
}

// MARK: - Root

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack {
                HomeView()
            }
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }

            NavigationStack {
                SearchView()
            }
            .tabItem {
                Label("Search", systemImage: "magnifyingglass")
            }

            NavigationStack {
                ChatbotView()
            }
            .tabItem {
                Label("AI", systemImage: "brain.head.profile")
            }

            NavigationStack {
                ProfileView()
            }
            .tabItem {
                Label("Profile", systemImage: "person.crop.circle")
            }
        }
        .tint(.primary)
    }
}

// MARK: - Home

struct HomeView: View {
    @StateObject private var vm = HomeViewModel()
    @State private var searchText: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Title only, centered
                Text("Finds")
                    .font(.largeTitle).bold()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
                    .padding(.horizontal)

                // Search Bar (local only visual, navigates to Search tab ideally)
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search movies, actors, genres…", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 6)
                )
                .padding(.horizontal)

                // Trending horizontal
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Trending")
                            .font(.headline)
                        if vm.isLoading { ProgressView().scaleEffect(0.8) }
                        Spacer()
                    }
                    .padding(.horizontal)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(vm.trending) { movie in
                                NavigationLink(value: movie) {
                                    TrendingCard(movie: movie)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                // Suggestions vertical
                VStack(alignment: .leading, spacing: 8) {
                    Text("For You")
                        .font(.headline)
                        .padding(.horizontal)

                    VStack(spacing: 12) {
                        ForEach(vm.suggestions) { movie in
                            NavigationLink(value: movie) {
                                SuggestionRow(movie: movie)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 16)
            }
        }
        .task {
            await vm.load()
        }
        .alert("Error", isPresented: .constant(vm.error != nil), actions: {
            Button("OK", role: .cancel) { vm.error = nil }
        }, message: {
            Text(vm.error ?? "")
        })
        .navigationDestination(for: Movie.self) { movie in
            MovieDetailView(movie: movie)
        }
        .background(LinearGradient(colors: [Color(.systemBackground), Color(.secondarySystemBackground)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Movie Detail

struct MovieDetailView: View {
    let movie: Movie
    @State private var isFavorite: Bool = false

    private var yearAndRuntimeText: String {
        let yearPart = movie.year > 0 ? "\(movie.year)" : nil
        let rtPart = movie.durationMinutes.map { "\($0) min" }
        switch (yearPart, rtPart) {
        case let (y?, r?):
            return "\(y) • \(r)"
        case let (y?, nil):
            return y
        case let (nil, r?):
            return r
        default:
            return ""
        }
    }

    var body: some View {
        ScrollView {
            ZStack {
                // Subtle background gradient
                LinearGradient(
                    colors: [Color(.secondarySystemBackground), Color(.systemBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 16) {
                    // Poster with refined style
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 12)
                            .overlay(
                                PosterView(url: movie.posterURL, fallbackSystemImage: "film")
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .padding(8)
                            )
                            .aspectRatio(2/3, contentMode: .fit)
                    }
                    .padding(.horizontal)

                    // Title + Rating + Favorite
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(movie.title)
                                .font(.title2).bold()

                            Text(yearAndRuntimeText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            StarRatingView(rating: movie.rating)
                        }
                        Spacer()
                        Button {
                            withAnimation(.spring(duration: 0.25)) {
                                isFavorite.toggle()
                            }
                        } label: {
                            Image(systemName: isFavorite ? "heart.fill" : "heart")
                                .font(.title2)
                                .foregroundStyle(isFavorite ? .red : .primary)
                                .padding(10)
                                .background(
                                    Circle().fill(.ultraThinMaterial)
                                        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 6)
                                )
                        }
                        .accessibilityLabel("Favorite")
                    }
                    .padding(.horizontal)

                    // Summary
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Summary")
                            .font(.headline)
                        Text(movie.summary.isEmpty ? "No overview available." : movie.summary)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)

                    // Reviews (mock)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("User Reviews")
                            .font(.headline)

                        VStack(spacing: 12) {
                            ForEach(MockData.reviews) { review in
                                ReviewRow(review: review)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Search

struct SearchView: View {
    @StateObject private var vm = SearchViewModel()

    let columns: [GridItem] = Array(repeating: .init(.flexible(), spacing: 12), count: 2)

    private var years: [Int] {
        let all = (1990...2025).reversed()
        return Array(all)
    }

    var body: some View {
        VStack(spacing: 12) {
            // Filters
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Keyword…", text: $vm.keyword)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .onSubmit {
                            Task { await vm.search() }
                        }

                    // Search button inside the search field
                    Button {
                        Task { await vm.search() }
                    } label: {
                        Image(systemName: "magnifyingglass.circle.fill")
                            .imageScale(.large)
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Search")
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ultraThinMaterial))

                HStack(spacing: 12) {
                    Menu {
                        Button("All Genres") { vm.selectedGenreID = nil }
                        Divider()
                        ForEach(vm.genres, id: \.id) { g in
                            Button(g.name) { vm.selectedGenreID = g.id }
                        }
                    } label: {
                        Label(vm.selectedGenreID.flatMap { id in vm.genres.first(where: { $0.id == id })?.name } ?? "Genre", systemImage: "line.3.horizontal.decrease.circle")
                            .frame(maxWidth: .infinity)
                    }

                    Menu {
                        Button("Any Year") { vm.selectedYear = nil }
                        Divider()
                        ForEach(years, id: \.self) { y in
                            Button("\(y)") { vm.selectedYear = y }
                        }
                    } label: {
                        Label(vm.selectedYear != nil ? "\(vm.selectedYear!)" : "Year", systemImage: "calendar")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // Grid results
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(vm.results) { movie in
                        NavigationLink(value: movie) {
                            MovieCardView(movie: movie)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }
        .task {
            await vm.loadGenres()
        }
        .alert("Error", isPresented: .constant(vm.error != nil), actions: {
            Button("OK", role: .cancel) { vm.error = nil }
        }, message: {
            Text(vm.error ?? "")
        })
        .navigationDestination(for: Movie.self) { movie in
            MovieDetailView(movie: movie)
        }
        .background(LinearGradient(colors: [Color(.systemBackground), Color(.secondarySystemBackground)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
    }
}


// MARK: - Chatbot

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isUser: Bool
}

struct ChatbotView: View {
    @State private var messages: [ChatMessage] = [
        ChatMessage(text: "Try: \"Recommend a comedy from the 2000s\"", isUser: false),
        ChatMessage(text: "Or: \"I feel nostalgic, what should I watch?\"", isUser: false)
    ]
    @State private var input: String = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(messages) { msg in
                            ChatBubble(message: msg)
                                .id(msg.id)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
                .onChange(of: messages) { _, _ in
                    if let last = messages.last?.id {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            HStack(spacing: 10) {
                TextField("Ask AI…", text: $input, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)

                Button {
                    send()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderedProminent)
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.all, 12)
            .background(.ultraThinMaterial)
        }
        .navigationTitle("AI Chatbot")
        .navigationBarTitleDisplayMode(.inline)
        .background(LinearGradient(colors: [Color(.systemBackground), Color(.secondarySystemBackground)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    private func send() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let userMsg = ChatMessage(text: trimmed, isUser: true)
        messages.append(userMsg)
        input = ""

        // Simulated AI response
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            messages.append(ChatMessage(text: "Here’s a suggestion based on your prompt: \(userMsg.text)", isUser: false))
        }
    }
}

// MARK: - Profile

struct ProfileView: View {
    @State private var watchlist: [Movie] = []
    @State private var watched: [Movie] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Header
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your Profile")
                            .font(.title2).bold()
                        Text("Manage your watchlist and stats")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal)

                // Watchlist
                SectionHeader("Watchlist")
                VStack(spacing: 12) {
                    if watchlist.isEmpty {
                        Text("Your watchlist is empty.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(watchlist) { movie in
                            NavigationLink(value: movie) {
                                SuggestionRow(movie: movie)
                            }
                        }
                    }
                }
                .padding(.horizontal)

                // Watched
                SectionHeader("Watched")
                VStack(spacing: 12) {
                    if watched.isEmpty {
                        Text("No watched movies yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(watched) { movie in
                            NavigationLink(value: movie) {
                                SuggestionRow(movie: movie)
                            }
                        }
                    }
                }
                .padding(.horizontal)

                // Stats
                SectionHeader("Statistics")
                StatsCard(watchCount: watched.count, watchlistCount: watchlist.count)
                    .padding(.horizontal)
                    .padding(.bottom, 24)
            }
        }
        .navigationDestination(for: Movie.self) { movie in
            MovieDetailView(movie: movie)
        }
        .background(LinearGradient(colors: [Color(.systemBackground), Color(.secondarySystemBackground)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Reusable UI

struct TrendingCard: View {
    let movie: Movie
    private var yearRuntime: String {
        let y = movie.year > 0 ? "\(movie.year)" : nil
        let r = movie.durationMinutes.map { "\($0) min" }
        switch (y, r) {
        case let (y?, r?):
            return "\(y) • \(r)"
        case let (y?, nil):
            return y
        case let (nil, r?):
            return r
        default:
            return ""
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // DEĞİŞİKLİK: Çerçeve ve gölge kaldırıldı, poster doğrudan gösteriliyor.
            PosterView(url: movie.posterURL, fallbackSystemImage: "film")
                .frame(width: 140, height: 210) // Posterin kendi boyutu
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous)) // Sadece posterin köşelerini yuvarla
                .shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 8) // Postere hafif bir gölge verilebilir
            

            Text(movie.title)
                .font(.subheadline).bold()
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(yearRuntime)
                .font(.caption)
                .foregroundStyle(.secondary)

            StarRatingView(rating: movie.rating, compact: true)
        }
        .frame(width: 140, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct SuggestionRow: View {
    let movie: Movie
    private var yearRuntime: String {
        let y = movie.year > 0 ? "\(movie.year)" : nil
        let r = movie.durationMinutes.map { "\($0) min" }
        switch (y, r) {
        case let (y?, r?):
            return "\(y) • \(r)"
        case let (y?, nil):
            return y
        case let (nil, r?):
            return r
        default:
            return ""
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .frame(width: 50, height: 75)
                    .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 4)

                PosterView(url: movie.posterURL, fallbackSystemImage: "film")
                    .frame(width: 50, height: 75)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(movie.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(yearRuntime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                StarRatingView(rating: movie.rating, compact: true)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 6)
        )
    }
}

struct MovieCardView: View {
    let movie: Movie
    private var yearRuntime: String {
        let y = movie.year > 0 ? "\(movie.year)" : nil
        let r = movie.durationMinutes.map { "\($0) min" }
        switch (y, r) {
        case let (y?, r?):
            return "\(y) • \(r)"
        case let (y?, nil):
            return y
        case let (nil, r?):
            return r
        default:
            return ""
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PosterView(url: movie.posterURL, fallbackSystemImage: "film")
                .aspectRatio(2/3, contentMode: .fill)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 8)
            
            Text(movie.title)
                .font(.subheadline).bold()
                .lineLimit(1)
            Text(yearRuntime)
                .font(.caption)
                .foregroundStyle(.secondary)
            StarRatingView(rating: movie.rating, compact: true)
        }
        .contentShape(Rectangle())
    }
}

// Refined PosterView with better loading/placeholder states and subtle gradient
struct PosterView: View {
    let url: URL?
    let fallbackSystemImage: String

    @State private var isLoading = true

    var body: some View {
        ZStack {
            // Background gradient for better contrast
            LinearGradient(
                colors: [Color(.tertiarySystemFill), Color(.secondarySystemFill)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Group {
                if let url {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .transition(.opacity.combined(with: .scale))
                                .onAppear { isLoading = false }

                        case .failure(_):
                            VStack(spacing: 8) {
                                Image(systemName: fallbackSystemImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 36, height: 36)
                                    .foregroundStyle(.secondary)
                                Text("No Image")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .onAppear { isLoading = false }

                        case .empty:
                            // Simple shimmer-like pulse
                            ProgressView()
                                .tint(.secondary)
                                .onAppear { isLoading = true }
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: fallbackSystemImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                            .foregroundStyle(.secondary)
                        Text("No Image")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .onAppear { isLoading = false }
                }
            }
        }
        .contentShape(Rectangle())
        .clipped()
    }
}

struct StarRatingView: View {
    let rating: Double
    var compact: Bool = false

    var body: some View {
        let fullStars = Int(rating.rounded(.down))
        let hasHalf = rating - Double(fullStars) >= 0.5
        let total = 5

        HStack(spacing: compact ? 2 : 4) {
            ForEach(0..<total, id: \.self) { idx in
                if idx < fullStars {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                } else if idx == fullStars && hasHalf {
                    Image(systemName: "star.leadinghalf.filled")
                        .foregroundStyle(.yellow)
                } else {
                    Image(systemName: "star")
                        .foregroundStyle(.yellow.opacity(0.6))
                }
            }
            if !compact {
                Text(String(format: "%.1f", rating))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ReviewRow: View {
    let review: Review
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 36, height: 36)
                .overlay(Image(systemName: "person.fill").foregroundStyle(.secondary))
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(review.userName).font(.subheadline).bold()
                    Spacer()
                    HStack(spacing: 2) {
                        ForEach(0..<5, id: \.self) { i in
                            Image(systemName: i < review.stars ? "star.fill" : "star")
                                .foregroundStyle(.yellow)
                                .font(.caption2)
                        }
                    }
                }
                Text(review.text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 6)
        )
    }
}

struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
        }
        .padding(.horizontal)
    }
}

struct StatsCard: View {
    let watchCount: Int
    let watchlistCount: Int
    var body: some View {
        HStack(spacing: 12) {
            StatTile(title: "Watched", value: "\(watchCount)", icon: "play.circle.fill", tint: .green)
            StatTile(title: "Watchlist", value: "\(watchlistCount)", icon: "bookmark.circle.fill", tint: .blue)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 8)
        )
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.headline)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Chat Bubbles

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isUser { Spacer(minLength: 40) }
            Text(message.text)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(message.isUser ? Color.blue.opacity(0.15) : Color.gray.opacity(0.15))
                        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 4)
                )
                .foregroundStyle(message.isUser ? .blue : .primary)
                .frame(maxWidth: UIScreen.main.bounds.width * 0.7, alignment: .leading)
            if !message.isUser { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
    }
}


// MARK: - Preview

#Preview {
    ContentView()
}
