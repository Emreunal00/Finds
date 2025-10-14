// MovieService.swift
import Foundation

protocol MovieServicing {
    func getTrending(page: Int) async throws -> [Movie]
    func getSuggestions(page: Int) async throws -> [Movie]
    func searchMovies(query: String, year: Int?, genreID: Int?, page: Int) async throws -> [Movie]
    func fetchGenres() async throws -> [TMDBGenre]
    // NEW: Multi Search
    func searchMulti(query: String, page: Int) async throws -> [Movie]

    // NEW: Details
    func fetchMovieRuntime(id: Int) async throws -> Int?
    func fetchTVRuntime(id: Int) async throws -> Int?
}

final class MovieService: MovieServicing {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func getTrending(page: Int = 1) async throws -> [Movie] {
        var comps = URLComponents(url: TMDBAPI.baseURL.appendingPathComponent("trending/movie/week"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "api_key", value: TMDBAPI.apiKey),
            .init(name: "language", value: "en-US"),
            .init(name: "page", value: String(page))
        ]
        let (data, _) = try await session.data(from: try comps.asURL())
        let resp = try JSONDecoder().decode(TMDBMovieResponse.self, from: data)
        var movies = resp.results.map { $0.toMovie() }

        // Süreleri paralel çek
        movies = try await enrichMoviesWithRuntime(fromMovies: resp.results, baseMovies: movies)
        return movies
    }

    func getSuggestions(page: Int = 1) async throws -> [Movie] {
        var comps = URLComponents(url: TMDBAPI.baseURL.appendingPathComponent("discover/movie"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "api_key", value: TMDBAPI.apiKey),
            .init(name: "language", value: "en-US"),
            .init(name: "sort_by", value: "popularity.desc"),
            .init(name: "vote_average.gte", value: "6.5"),
            .init(name: "page", value: String(page))
        ]
        let (data, _) = try await session.data(from: try comps.asURL())
        let resp = try JSONDecoder().decode(TMDBMovieResponse.self, from: data)
        var movies = resp.results.map { $0.toMovie() }

        movies = try await enrichMoviesWithRuntime(fromMovies: resp.results, baseMovies: movies)
        return movies
    }

    func searchMovies(query: String, year: Int?, genreID: Int?, page: Int = 1) async throws -> [Movie] {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return []
        }
        var comps = URLComponents(url: TMDBAPI.baseURL.appendingPathComponent("search/movie"), resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [
            .init(name: "api_key", value: TMDBAPI.apiKey),
            .init(name: "language", value: "en-US"),
            .init(name: "query", value: query),
            .init(name: "include_adult", value: "false"),
            .init(name: "page", value: String(page))
        ]
        if let year { items.append(.init(name: "year", value: String(year))) }
        comps.queryItems = items

        let (data, _) = try await session.data(from: try comps.asURL())
        let resp = try JSONDecoder().decode(TMDBMovieResponse.self, from: data)
        var tmdbMovies = resp.results
        if let genreID {
            tmdbMovies = tmdbMovies.filter { $0.genreIDs?.contains(genreID) == true }
        }
        var movies = tmdbMovies.map { $0.toMovie() }
        movies = try await enrichMoviesWithRuntime(fromMovies: tmdbMovies, baseMovies: movies)
        return movies
    }

    func fetchGenres() async throws -> [TMDBGenre] {
        var comps = URLComponents(url: TMDBAPI.baseURL.appendingPathComponent("genre/movie/list"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "api_key", value: TMDBAPI.apiKey),
            .init(name: "language", value: "en-US")
        ]
        let (data, _) = try await session.data(from: try comps.asURL())
        let list = try JSONDecoder().decode(TMDBGenreList.self, from: data)
        return list.genres
    }

    // MARK: - Multi Search

    func searchMulti(query: String, page: Int = 1) async throws -> [Movie] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }

        var comps = URLComponents(url: TMDBAPI.baseURL.appendingPathComponent("search/multi"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "api_key", value: TMDBAPI.apiKey),
            .init(name: "language", value: "en-US"),
            .init(name: "query", value: trimmed),
            .init(name: "include_adult", value: "false"),
            .init(name: "page", value: String(page))
        ]

        let (data, _) = try await session.data(from: try comps.asURL())
        let resp = try JSONDecoder().decode(TMDBMultiSearchResponse.self, from: data)

        // person dışındakileri Movie’a map et
        var mapped: [Movie] = resp.results.compactMap { $0.toMovie() }

        // Süreleri paralel çek: mediaType = movie/tv
        mapped = try await enrichMultiWithRuntime(results: resp.results, baseMovies: mapped)

        return mapped
    }

    // MARK: - Details

    func fetchMovieRuntime(id: Int) async throws -> Int? {
        var comps = URLComponents(url: TMDBAPI.baseURL.appendingPathComponent("movie/\(id)"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "api_key", value: TMDBAPI.apiKey),
            .init(name: "language", value: "en-US")
        ]
        let (data, _) = try await session.data(from: try comps.asURL())
        let detail = try JSONDecoder().decode(TMDBMovieDetail.self, from: data)
        return detail.runtime
    }

    func fetchTVRuntime(id: Int) async throws -> Int? {
        var comps = URLComponents(url: TMDBAPI.baseURL.appendingPathComponent("tv/\(id)"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "api_key", value: TMDBAPI.apiKey),
            .init(name: "language", value: "en-US")
        ]
        let (data, _) = try await session.data(from: try comps.asURL())
        let detail = try JSONDecoder().decode(TMDBTVDetail.self, from: data)
        // episode_run_time bir dizi; ilk değeri kullanıyoruz
        return detail.episodeRunTime?.first
    }

    // MARK: - Helpers to enrich runtime

    private func enrichMoviesWithRuntime(fromMovies tmdb: [TMDBMovie], baseMovies: [Movie]) async throws -> [Movie] {
        // TMDBMovie listesi film (movie) içeriyor; her biri için runtime çek
        let ids = tmdb.map { $0.id }
        // Paralel istekler
        let runtimes: [Int?] = try await withThrowingTaskGroup(of: (Int, Int?).self) { group in
            for id in ids {
                group.addTask {
                    let rt = try await self.fetchMovieRuntime(id: id)
                    return (id, rt)
                }
            }
            var map: [Int: Int?] = [:]
            for try await (id, rt) in group {
                map[id] = rt
            }
            // baseMovies ile aynı sırada döndürmek için
            return ids.map { map[$0] ?? nil }
        }

        // baseMovies Movie struct’ında TMDb id’si yok; bu yüzden sıraya göre eşliyoruz.
        // Öneri: Movie’ye tmdbID eklemek ileride faydalı olur. Şimdilik sırayı koruyoruz.
        return zip(baseMovies, runtimes).map { (movie, rt) in
            var m = movie
            m.durationMinutes = rt
            return m
        }
    }

    private func enrichMultiWithRuntime(results: [TMDBMultiResult], baseMovies: [Movie]) async throws -> [Movie] {
        // Sadece movie/tv olanlar maplenmiş durumda. Sıra korunuyor.
        // Her bir result için uygun endpoint’ten runtime çek.
        let fetchTasks = results.enumerated().compactMap { (idx, r) -> (Int, () async throws -> Int?)? in
            guard r.mediaType == "movie" || r.mediaType == "tv" else { return nil }
            if r.mediaType == "movie" {
                return (idx, { try await self.fetchMovieRuntime(id: r.id) })
            } else {
                return (idx, { try await self.fetchTVRuntime(id: r.id) })
            }
        }

        let runtimeByIndex: [Int: Int?] = try await withThrowingTaskGroup(of: (Int, Int?).self) { group in
            for (idx, task) in fetchTasks {
                group.addTask {
                    let rt = try await task()
                    return (idx, rt)
                }
            }
            var dict: [Int: Int?] = [:]
            for try await (idx, rt) in group {
                dict[idx] = rt
            }
            return dict
        }

        var enriched = baseMovies
        for (idx, rt) in runtimeByIndex {
            guard idx < enriched.count else { continue }
            enriched[idx].durationMinutes = rt
        }
        return enriched
    }
}

private extension URLComponents {
    func asURL() throws -> URL {
        guard let url = url else { throw URLError(.badURL) }
        return url
    }
}
