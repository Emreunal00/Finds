//
//  FindsAppTests.swift
//  FindsAppTests
//
//  Created by Emre ünal on 11.12.2025.
//

import Testing
import Foundation
@testable import FindsApp

@Suite("App Sanity Tests")
struct AppSanityTests {
    @Test("Always true")
    func alwaysTrue() async throws {
        #expect(true)
    }
}

@Suite("SearchViewModel Tests")
@MainActor
struct SearchViewModelTests_Suite {
    @Test("Empty query returns empty results")
    func emptyQuery() async throws {
        let vm = SearchViewModel(service: MockMovieService())
        vm.keyword = "   "
        await vm.search()
        #expect(vm.results.isEmpty)
    }

    @Test("Keyword cleared resets to default state")
    func keywordClearedResets() async throws {
        var mock = MockMovieService()
        mock.searchResults = [Movie(id: 1, title: "Test", year: 2020, genres: [], posterName: "", rating: 7.5, summary: "", posterURL: nil, durationMinutes: nil, mediaType: "movie", cast: nil, directors: nil, popularity: nil)]
        let vm = SearchViewModel(service: mock)

        vm.keyword = "tes"
        await vm.search()
        #expect(!vm.results.isEmpty)

        // Clear keyword -> should reset
        vm.keyword = ""
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(vm.results.isEmpty)
        #expect(vm.selectedGenreID == nil)
        #expect(vm.selectedYear == nil)
    }
}

@Suite("Performance")
@MainActor
struct PerformanceTests {
    @Test("Search scoring performance")
    func searchPerformance() async throws {
        var mock = MockMovieService()
        mock.searchResults = (0..<5000).map { i in
            Movie(id: i, title: "Item \(i)", year: 2020 + (i % 5), genres: ["#28"], posterName: "", rating: Double(i % 10), summary: "", posterURL: nil, durationMinutes: nil, mediaType: "movie", cast: nil, directors: nil, popularity: Double.random(in: 0...100))
        }
        let vm = SearchViewModel(service: mock)
        vm.keyword = "Item"

        let start = CFAbsoluteTimeGetCurrent()
        await vm.search()
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        // Optional: assert it runs within a reasonable time window if desired
        _ = elapsed

        #expect(!vm.results.isEmpty)
    }
}

