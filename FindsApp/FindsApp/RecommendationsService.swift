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
        // content_id may be String or Int
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
        // year may be Int or String
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

final class RecommendationsService {
    private let baseURL = URL(string: "https://finds-api-91195881425.europe-west3.run.app")!

    enum ServiceError: Error { case badURL, badResponse, decoding }

    private func fetch(type: String, userID: String) async throws -> [RecommendationDTO] {
        var comps = URLComponents(url: baseURL.appendingPathComponent("api/v1/recommendations"), resolvingAgainstBaseURL: false)
        comps?.queryItems = [
            URLQueryItem(name: "userId", value: userID),
            URLQueryItem(name: "type", value: type)
        ]
        guard let url = comps?.url else { throw ServiceError.badURL }
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

    func fetchRecommendedMovies(userID: String) async throws -> [Movie] {
        let dtos = try await fetch(type: "movie", userID: userID)
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

    func fetchRecommendedShows(userID: String) async throws -> [Movie] {
        let dtos = try await fetch(type: "tv", userID: userID)
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
}
