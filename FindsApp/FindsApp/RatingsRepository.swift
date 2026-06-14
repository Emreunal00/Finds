


import Foundation
import FirebaseFirestore

struct RatingAggregate { let total: Double; let count: Int; var average: Double { count > 0 ? total / Double(count) : 0 } }

final class RatingsRepository {
    private let db = Firestore.firestore()

    private func ratingDocKey(movieID: Int, type: String) -> String { "\(type.lowercased()):\(movieID)" }

    func fetchAggregate(movieID: Int, type: String) async throws -> RatingAggregate? {
        let key = ratingDocKey(movieID: movieID, type: type)
        let snap = try await db.collection("ratings").document(key).getDocument()
        guard let data = snap.data() else { return nil }
        let total = data["total"] as? Double ?? 0
        let count = data["count"] as? Int ?? 0
        return RatingAggregate(total: total, count: count)
    }

    func fetchUserRating(uid: String, movieID: Int, type: String) async throws -> Double? {
        let key = ratingDocKey(movieID: movieID, type: type)
        let snap = try await db.collection("ratings").document(key)
            .collection("userRatings").document(uid).getDocument()
        return snap.data()?["rating"] as? Double
    }

    func submitRating(uid: String, movieID: Int, type: String, value: Double) async throws -> RatingAggregate {
        let key = ratingDocKey(movieID: movieID, type: type)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RatingAggregate, Error>) in
            self.db.runTransaction({ (txn, errPtr) -> Any? in
                let aggRef = self.db.collection("ratings").document(key)
                let userRef = aggRef.collection("userRatings").document(uid)

                do {
                    
                    var aggSnap: DocumentSnapshot
                    do {
                        aggSnap = try txn.getDocument(aggRef)
                    } catch {
                        txn.setData(["total": 0.0, "count": 0], forDocument: aggRef, merge: true)
                        aggSnap = try txn.getDocument(aggRef)
                    }
                    let currentTotal = (aggSnap.data()? ["total"] as? Double) ?? 0.0
                    let currentCount = (aggSnap.data()? ["count"] as? Int) ?? 0

                    
                    let userSnap = try? txn.getDocument(userRef)
                    let old = (userSnap?.data()? ["rating"] as? Double)

                    var newTotal = currentTotal
                    var newCount = currentCount
                    if let old { newTotal += (value - old) } else { newTotal += value; newCount += 1 }

                    txn.setData(["total": newTotal, "count": newCount], forDocument: aggRef, merge: true)
                    txn.setData(["rating": value, "updatedAt": FieldValue.serverTimestamp()], forDocument: userRef, merge: true)

                    
                    return RatingAggregate(total: newTotal, count: newCount)
                } catch {
                    
                    if let errPtr {
                        errPtr.pointee = error as NSError
                    }
                    return nil
                }
            }) { (result, error) in
                if let error {
                    continuation.resume(throwing: error)
                } else if let aggregate = result as? RatingAggregate {
                    continuation.resume(returning: aggregate)
                } else {
                    continuation.resume(throwing: NSError(domain: "RatingsRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Transaction returned no result"]))
                }
            }
        }
    }

    func deleteRating(uid: String, movieID: Int, type: String, previousValue: Double) async throws -> RatingAggregate {
        let key = ratingDocKey(movieID: movieID, type: type)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RatingAggregate, Error>) in
            self.db.runTransaction({ (txn, errPtr) -> Any? in
                let aggRef = self.db.collection("ratings").document(key)
                let userRef = aggRef.collection("userRatings").document(uid)

                do {
                    
                    var aggSnap: DocumentSnapshot
                    do {
                        aggSnap = try txn.getDocument(aggRef)
                    } catch {
                        
                        if let errPtr { errPtr.pointee = NSError(domain: "RatingsRepository", code: -2, userInfo: [NSLocalizedDescriptionKey: "Aggregate not found"]) }
                        return nil
                    }
                    let currentTotal = (aggSnap.data()? ["total"] as? Double) ?? 0.0
                    let currentCount = (aggSnap.data()? ["count"] as? Int) ?? 0

                    
                    let userSnap = try? txn.getDocument(userRef)
                    let existing = (userSnap?.data()? ["rating"] as? Double)

                    guard existing != nil else {
                        
                        let aggregate = RatingAggregate(total: currentTotal, count: currentCount)
                        return aggregate
                    }

                    
                    let newTotal = currentTotal - previousValue
                    let newCount = max(0, currentCount - 1)

                    
                    txn.setData(["total": newTotal, "count": newCount], forDocument: aggRef, merge: true)
                    txn.deleteDocument(userRef)

                    return RatingAggregate(total: newTotal, count: newCount)
                } catch {
                    if let errPtr { errPtr.pointee = error as NSError }
                    return nil
                }
            }) { (result, error) in
                if let error {
                    continuation.resume(throwing: error)
                } else if let aggregate = result as? RatingAggregate {
                    continuation.resume(returning: aggregate)
                } else {
                    continuation.resume(throwing: NSError(domain: "RatingsRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Transaction returned no result"]))
                }
            }
        }
    }
}
