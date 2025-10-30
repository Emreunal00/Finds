import Foundation
import FirebaseStorage
import UIKit

struct StorageService {
    private let storage = Storage.storage()

    func uploadProfileImage(data: Data, for uid: String) async throws -> String {
        let ref = storage.reference().child("profilePhotos/\(uid).jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        let _ = try await ref.putDataAsync(data, metadata: metadata)
        let url = try await ref.downloadURL()
        return url.absoluteString
    }
}

private extension StorageReference {
    func putDataAsync(_ data: Data, metadata: StorageMetadata?) async throws -> StorageMetadata {
        try await withCheckedThrowingContinuation { continuation in
            self.putData(data, metadata: metadata) { meta, error in
                if let error { continuation.resume(throwing: error) }
                else if let meta { continuation.resume(returning: meta) }
                else { continuation.resume(throwing: NSError(domain: "Storage", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown storage error"])) }
            }
        }
    }

    func downloadURL() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.downloadURL { url, error in
                if let error { continuation.resume(throwing: error) }
                else if let url { continuation.resume(returning: url) }
                else { continuation.resume(throwing: NSError(domain: "Storage", code: -2, userInfo: [NSLocalizedDescriptionKey: "No URL"])) }
            }
        }
    }
}
