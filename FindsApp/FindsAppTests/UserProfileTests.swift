


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
        #expect(profile.watchedIDs.isEmpty)
        #expect(profile.profiles.isEmpty)
    }
    @Test("New profile is Equatable")
    func testProfileEquatable() {
        let fixedDate = Date(timeIntervalSince1970: 1234567890)
        let profile = Profile(id: "profile", displayName: "Reader", createdAt: fixedDate)
        let p1 = UserProfile(id: "uid", email: "a@b.com", profiles: [profile], selectedProfileID: profile.id)
        let p2 = UserProfile(id: "uid", email: "a@b.com", profiles: [profile], selectedProfileID: profile.id)
        #expect(p1 == p2)
    }
}
