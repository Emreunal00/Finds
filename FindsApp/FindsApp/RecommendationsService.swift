import Foundation

struct RecommendationDTO: Decodable {
    let contentID: String
    let type: String?
    let title: String
    let posterURLString: String?
    let year: Int?

    enum CodingKeys: String, CodingKey { case content_id, type, title, poster_url, year }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        
        if let s = try? c.decode(String.self, forKey: .content_id) {
            self.contentID = s
        } else if let i = try? c.decode(Int.self, forKey: .content_id) {
            self.contentID = String(i)
        } else {
            self.contentID = "0"
        }
        self.type = try? c.decode(String.self, forKey: .type)
        self.title = (try? c.decode(String.self, forKey: .title)) ?? ""
        self.posterURLString = try? c.decode(String.self, forKey: .poster_url)
        
        if let yi = try? c.decode(Int.self, forKey: .year) {
            self.year = yi
        } else if let ys = try? c.decode(String.self, forKey: .year), let yi = Int(ys) {
            self.year = yi
        } else {
            self.year = nil
        }
    }
}

struct RecommendationsEnvelope: Decodable {
    let bot_message: String?
    let recommendations: [RecommendationDTO]
}

private struct BookRecommendationsEnvelope: Decodable {
    let books: [BookRecommendationDTO]
}

private struct BookRecommendationDTO: Decodable {
    let bookID: String
    let title: String
    let authors: [String]
    let genre: String?
    let imageURLString: String?
    let publishedYear: Int?
    let matchScore: Double?

    enum CodingKeys: String, CodingKey {
        case bookID = "book_id"
        case title, authors, genre
        case imageURLString = "image_url"
        case publishedYear = "published_year"
        case matchScore = "match_score"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bookID = try container.decode(String.self, forKey: .bookID)
        title = (try? container.decode(String.self, forKey: .title)) ?? "Untitled"
        genre = try? container.decode(String.self, forKey: .genre)
        imageURLString = try? container.decode(String.self, forKey: .imageURLString)
        matchScore = try? container.decode(Double.self, forKey: .matchScore)

        if let values = try? container.decode([String].self, forKey: .authors) {
            authors = values
        } else if let value = try? container.decode(String.self, forKey: .authors) {
            authors = value
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        } else {
            authors = []
        }

        if let value = try? container.decode(Int.self, forKey: .publishedYear) {
            publishedYear = value
        } else if let value = try? container.decode(String.self, forKey: .publishedYear) {
            publishedYear = Int(value)
        } else {
            publishedYear = nil
        }
    }
}

final class RecommendationsService {
    enum ServiceError: Error { case badURL, badResponse, decoding }

    private func fetch(type: String, userID: String, profileID: String) async throws -> [RecommendationDTO] {
        guard let url = FindsAPI.url(
            path: "api/v1/recommendations",
            queryItems: [
                URLQueryItem(name: "userId", value: userID),
                URLQueryItem(name: "profileId", value: profileID),
                URLQueryItem(name: "type", value: type)
            ]
        ) else { throw ServiceError.badURL }
        #if DEBUG
        print("[RecommendationsService] GET \(url.absoluteString)")
        #endif
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<no body>"
            #if DEBUG
            print("[RecommendationsService] HTTP \(http.statusCode) body: \(body)")
            #endif
            throw ServiceError.badResponse
        }
        let decoder = JSONDecoder()
        do {
            let env = try decoder.decode(RecommendationsEnvelope.self, from: data)
            return env.recommendations
        } catch {
            #if DEBUG
            let body = String(data: data, encoding: .utf8) ?? "<invalid json>"
            print("[RecommendationsService] Decoding failed. Body: \(body)")
            #endif
            throw ServiceError.decoding
        }
    }

    func fetchRecommendedMovies(userID: String, profileID: String) async throws -> [Movie] {
        let dtos = try await fetch(type: "movie", userID: userID, profileID: profileID)
        return dtos.map { dto in
            Movie(
                id: Int(dto.contentID) ?? abs(dto.contentID.hashValue),
                title: dto.title,
                year: dto.year ?? 0,
                posterName: "",
                posterURL: dto.posterURLString.flatMap(URL.init(string:)),
                mediaType: dto.type ?? "movie"
            )
        }
    }

    func fetchRecommendedShows(userID: String, profileID: String) async throws -> [Movie] {
        let dtos = try await fetch(type: "tv", userID: userID, profileID: profileID)
        return dtos.map { dto in
            Movie(
                id: Int(dto.contentID) ?? abs(dto.contentID.hashValue),
                title: dto.title,
                year: dto.year ?? 0,
                posterName: "",
                posterURL: dto.posterURLString.flatMap(URL.init(string:)),
                mediaType: dto.type ?? "tv"
            )
        }
    }

    func fetchRecommendedBooks(userID: String, profileID: String, count: Int = 30) async throws -> [Movie] {
        guard let url = FindsAPI.url(
            path: "api/v1/book-recommendations",
            queryItems: [
                URLQueryItem(name: "userId", value: userID),
                URLQueryItem(name: "profileId", value: profileID),
                URLQueryItem(name: "count", value: String(count))
            ]
        ) else { throw ServiceError.badURL }
        #if DEBUG
        print("[RecommendationsService] GET \(url.absoluteString)")
        #endif

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            #if DEBUG
            let body = String(data: data, encoding: .utf8) ?? "<no body>"
            print("[RecommendationsService] Book recommendations failed. Body: \(body)")
            #endif
            throw ServiceError.badResponse
        }

        do {
            let envelope = try JSONDecoder().decode(BookRecommendationsEnvelope.self, from: data)
            return envelope.books.map { dto in
                Movie(
                    id: Self.stableNumericID(for: dto.bookID),
                    title: dto.title,
                    year: dto.publishedYear ?? 0,
                    genres: dto.genre.map { [$0] } ?? [],
                    posterName: "",
                    rating: dto.matchScore ?? 0,
                    posterURL: Self.normalizedURL(from: dto.imageURLString),
                    mediaType: "book",
                    externalContentID: dto.bookID,
                    directors: dto.authors
                )
            }
        } catch {
            #if DEBUG
            let body = String(data: data, encoding: .utf8) ?? "<invalid json>"
            print("[RecommendationsService] Book decoding failed. Body: \(body)")
            #endif
            throw ServiceError.decoding
        }
    }

    private static func normalizedURL(from value: String?) -> URL? {
        value
            .map { $0.replacingOccurrences(of: "http://", with: "https://") }
            .flatMap(URL.init(string:))
    }

    private static func stableNumericID(for string: String) -> Int {
        var hash: UInt64 = 1469598103934665603
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return Int(hash & 0x7fffffff)
    }
}
