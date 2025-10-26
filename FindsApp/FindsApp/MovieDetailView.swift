import SwiftUI

struct MovieDetailView: View {
    let movie: Movie

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerPoster
                titleSection
                metaSection
                if !movie.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(movie.summary)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .padding(.top, 4)
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
    }

    private var headerPoster: some View {
        Group {
            if let url = movie.posterURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ZStack {
                            Color(.tertiarySystemFill)
                            ProgressView()
                        }
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
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
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                placeholder
            }
        }
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(movie.title)
                .font(.title2).bold()
            HStack(spacing: 8) {
                if movie.year > 0 {
                    Text(String(movie.year))
                }
                if movie.rating > 0 {
                    Label(String(format: "%.1f", movie.rating), systemImage: "star.fill")
                        .symbolRenderingMode(.hierarchical)
                }
                if let runtime = movie.durationMinutes {
                    Label("\(runtime) min", systemImage: "clock")
                        .symbolRenderingMode(.hierarchical)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private var metaSection: some View {
        let readableGenres: [String] = movie.genres.map { token in
            if token.hasPrefix("#"), let id = Int(token.dropFirst()) {
                return "#\(id)"
            }
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
            Image(systemName: "film")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
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
        durationMinutes: 123
    )
    return NavigationStack {
        MovieDetailView(movie: sample)
    }
}
