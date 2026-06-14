


import Foundation

struct RatingsStore {
    private static let userRatingsKey = "user_movie_ratings_v1" 
    private static let aggregatesKey = "movie_aggregates_v1"     

    struct Aggregate: Codable {
        var total: Double
        var count: Int
        var average: Double { count > 0 ? total / Double(count) : 0 }
    }

    
    private static var userCache: [String: Double] = {
        if let data = UserDefaults.standard.data(forKey: userRatingsKey),
           let decoded = try? JSONDecoder().decode([String: Double].self, from: data) {
            return decoded
        }
        return [:]
    }()

    private static var aggregatesCache: [String: Aggregate] = {
        if let data = UserDefaults.standard.data(forKey: aggregatesKey),
           let decoded = try? JSONDecoder().decode([String: Aggregate].self, from: data) {
            return decoded
        }
        return [:]
    }()

    private static func userKey(userID: String, movieID: Int, type: String) -> String {
        "\(userID):\(type.lowercased()):\(movieID)"
    }

    private static func movieKey(movieID: Int, type: String) -> String {
        "\(type.lowercased()):\(movieID)"
    }

    
    static func rating(for userID: String, movieID: Int, type: String) -> Double? {
        userCache[userKey(userID: userID, movieID: movieID, type: type)]
    }

    static func setRating(_ rating: Double, for userID: String, movieID: Int, type: String) {
        userCache[userKey(userID: userID, movieID: movieID, type: type)] = rating
        persistUser()
    }

    static func removeRating(for userID: String, movieID: Int, type: String) {
        userCache.removeValue(forKey: userKey(userID: userID, movieID: movieID, type: type))
        persistUser()
    }

    
    static func aggregate(for movieID: Int, type: String) -> Aggregate {
        aggregatesCache[movieKey(movieID: movieID, type: type)] ?? Aggregate(total: 0, count: 0)
    }

    static func applyDelta(for movieID: Int, type: String, add value: Double, incrementCount: Bool) -> Aggregate {
        let key = movieKey(movieID: movieID, type: type)
        var agg = aggregatesCache[key] ?? Aggregate(total: 0, count: 0)
        agg.total += value
        if incrementCount { agg.count += 1 }
        aggregatesCache[key] = agg
        persistAggregates()
        return agg
    }

    static func setAggregate(total: Double, count: Int, for movieID: Int, type: String) {
        let key = movieKey(movieID: movieID, type: type)
        aggregatesCache[key] = Aggregate(total: total, count: count)
        persistAggregates()
    }

    
    private static func persistUser() {
        if let data = try? JSONEncoder().encode(userCache) {
            UserDefaults.standard.set(data, forKey: userRatingsKey)
        }
    }

    private static func persistAggregates() {
        if let data = try? JSONEncoder().encode(aggregatesCache) {
            UserDefaults.standard.set(data, forKey: aggregatesKey)
        }
    }
}
