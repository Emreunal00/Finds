import Foundation

private struct GoogleBooksResponse: Decodable {
    let items: [GoogleBookItem]?
}

private struct GoogleBookItem: Decodable {
    let id: String
    let volumeInfo: GoogleBookVolumeInfo
}

private struct GoogleBookVolumeInfo: Decodable {
    let title: String?
    let authors: [String]?
    let publishedDate: String?
    let description: String?
    let categories: [String]?
    let averageRating: Double?
    let ratingsCount: Int?
    let imageLinks: GoogleBookImageLinks?
}

private struct GoogleBookImageLinks: Decodable {
    let thumbnail: String?
    let smallThumbnail: String?
}

enum BookCatalog {
    private static let apiKey = "AIzaSyBCB5jvMDiK202aY7UnSlipclxg4I7hIM8"
    private static let baseURL = URL(string: "https://www.googleapis.com/books/v1/volumes")!

    private actor BookStore {
        private var cachedByExternalID: [String: Movie] = [:]
        private var cachedByNumericID: [Int: Movie] = [:]

        func store(_ books: [Movie]) {
            for book in books {
                if let externalID = book.externalContentID {
                    cachedByExternalID[externalID] = book
                }
                cachedByNumericID[book.id] = book
            }
        }

        func book(numericID: Int) -> Movie? {
            cachedByNumericID[numericID]
        }

        func book(externalID: String) -> Movie? {
            cachedByExternalID[externalID]
        }
    }

    private static let store = BookStore()

    static func trendingBooks(page: Int = 1, pageSize: Int = 20) async -> [Movie] {
        await fetchBooksPage(query: "subject:fiction", orderBy: "relevance", page: page, pageSize: pageSize)
    }

    static func recommendedBooks(for userID: String?, page: Int = 1, pageSize: Int = 20) async -> [Movie] {
        await fetchBooksPage(query: "subject:fiction", orderBy: "newest", page: page, pageSize: pageSize)
    }

    static func searchBooks(query: String, maxResults: Int = 12) async -> [Movie] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }
        return await fetchBooks(query: trimmedQuery, orderBy: "relevance", maxResults: maxResults)
    }

    static func fetchBook(id: Int, externalContentID: String? = nil) async throws -> Movie {
        if let externalContentID,
           let cached = await store.book(externalID: externalContentID) {
            return cached
        }
        if let cached = await store.book(numericID: id) {
            return cached
        }
        guard let externalContentID else {
            throw NSError(domain: "BookCatalog", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "Book not found."
            ])
        }

        let url = baseURL.appending(path: externalContentID).appending(queryItems: [
            URLQueryItem(name: "key", value: apiKey)
        ])
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "BookCatalog", code: 500, userInfo: [
                NSLocalizedDescriptionKey: "Failed to load book."
            ])
        }

        let item = try JSONDecoder().decode(GoogleBookItem.self, from: data)
        let movie = map(item: item)
        await store.store([movie])
        return movie
    }

    static func fetchMedia(id: Int, type: String, externalContentID: String? = nil, service: MovieServicing = MovieService()) async throws -> Movie {
        switch type.lowercased() {
        case "book":
            return try await fetchBook(id: id, externalContentID: externalContentID)
        case "tv":
            return try await service.fetchTVBasic(id: id)
        default:
            return try await service.fetchMovieBasic(id: id)
        }
    }

    static func symbolName(for movie: Movie) -> String {
        movie.isBook ? "book.closed" : "film"
    }

    private static func fetchBooks(query: String, orderBy: String, maxResults: Int) async -> [Movie] {
        let clampedTarget = max(1, min(maxResults, 250))
        let pageSize = 30
        var collected: [Movie] = []
        var seenExternalIDs = Set<String>()
        var page = 1

        while collected.count < clampedTarget {
            let batchSize = min(pageSize, clampedTarget - collected.count)
            let books = await fetchBooksPage(query: query, orderBy: orderBy, page: page, pageSize: batchSize)
            if books.isEmpty { break }

            let uniqueBooks = books.filter { book in
                guard let externalID = book.externalContentID else { return false }
                return seenExternalIDs.insert(externalID).inserted
            }

            collected.append(contentsOf: uniqueBooks)
            if books.count < batchSize { break }
            page += 1
        }

        return Array(collected.prefix(clampedTarget))
    }

    private static func fetchBooksPage(query: String, orderBy: String, page: Int, pageSize: Int) async -> [Movie] {
        let clampedPage = max(1, page)
        let clampedPageSize = max(1, min(pageSize, 40))
        let startIndex = (clampedPage - 1) * clampedPageSize
        guard let url = booksURL(
            query: query,
            orderBy: orderBy,
            maxResults: clampedPageSize,
            startIndex: startIndex
        ) else { return [] }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return []
            }
            let decoded = try JSONDecoder().decode(GoogleBooksResponse.self, from: data)
            let books = (decoded.items ?? []).map(map(item:))
            await store.store(books)
            return books
        } catch {
            print("[BookCatalog] fetch failed:", error.localizedDescription)
            return []
        }
    }

    private static func booksURL(query: String, orderBy: String, maxResults: Int, startIndex: Int) -> URL? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "orderBy", value: orderBy),
            URLQueryItem(name: "printType", value: "books"),
            URLQueryItem(name: "langRestrict", value: "en"),
            URLQueryItem(name: "maxResults", value: String(maxResults)),
            URLQueryItem(name: "startIndex", value: String(startIndex)),
            URLQueryItem(name: "key", value: apiKey)
        ]
        return components?.url
    }

    private static func map(item: GoogleBookItem) -> Movie {
        let info = item.volumeInfo
        let publishedYear = extractYear(from: info.publishedDate)
        let posterURLString = info.imageLinks?.thumbnail ?? info.imageLinks?.smallThumbnail
        let normalizedPosterURL = posterURLString?
            .replacingOccurrences(of: "http://", with: "https://")

        return Movie(
            id: stableNumericID(for: item.id),
            title: info.title ?? "Untitled",
            year: publishedYear,
            genres: info.categories ?? [],
            posterName: "",
            rating: info.averageRating ?? 0,
            summary: info.description ?? "",
            posterURL: normalizedPosterURL.flatMap(URL.init(string:)),
            durationMinutes: nil,
            mediaType: "book",
            externalContentID: item.id,
            cast: nil,
            directors: info.authors,
            popularity: Double(info.ratingsCount ?? 0)
        )
    }

    private static func stableNumericID(for string: String) -> Int {
        var hash: UInt64 = 1469598103934665603
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return Int(hash & 0x7fffffff)
    }

    private static func extractYear(from publishedDate: String?) -> Int {
        guard let publishedDate else { return 0 }
        let prefix = publishedDate.prefix(4)
        return Int(prefix) ?? 0
    }
}
