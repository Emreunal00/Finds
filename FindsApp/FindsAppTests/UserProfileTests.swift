//
//  UserProfileTests.swift
//
import Foundation
import Testing
@testable import FindsApp

@Suite("UserProfile Model Tests")
struct UserProfileTests {
    @Test("Create and check empty profile")
    func testEmptyProfile() {
        let profile = UserProfile.empty(uid: "abc", email: "mail@test.com")
        #expect(profile.id == "abc")
        #expect(profile.email == "mail@test.com")
        #expect(profile.watchlistIDs.isEmpty)
        #expect(profile.watchedEntries.isEmpty)
    }
    @Test("New profile is Equatable")
    func testProfileEquatable() {
        let fixedDate = Date(timeIntervalSince1970: 1234567890)
        let p1 = UserProfile(id: "uid", email: "a@b.com", displayName: nil, photoURL: nil, createdAt: fixedDate, watchlistIDs: [], watchedIDs: [], favoritesIDs: [], watchedEntries: [], favoritesEntries: [], watchlistEntries: [])
        let p2 = UserProfile(id: "uid", email: "a@b.com", displayName: nil, photoURL: nil, createdAt: fixedDate, watchlistIDs: [], watchedIDs: [], favoritesIDs: [], watchedEntries: [], favoritesEntries: [], watchlistEntries: [])
        #expect(p1 == p2)
    }
}
