import Foundation

enum FindsAPI {
    static let baseURL = URL(string: "https://finds-api-91195881425.europe-west3.run.app")!

    static func url(path: String, queryItems: [URLQueryItem] = []) -> URL? {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        return components?.url
    }
}
