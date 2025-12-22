//
//  SearchViewModelTests.swift
//  FindsApp
//
//  Created by Emre ünal on 11.12.2025.
//


import Testing
@testable import FindsApp

@Suite("SearchViewModel Tests")
@MainActor
struct SearchViewModelTests {
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

        vm.keyword = "" // clear
        await Task.yield()
        #expect(vm.results.isEmpty)
        #expect(vm.selectedGenreID == nil)
        #expect(vm.selectedYear == nil)
    }

    @Test("Performance: search sorting/scoring")
    func performanceSearch() async throws {
        var mock = MockMovieService()
        mock.searchResults = (0..<5000).map { i in
            Movie(id: i, title: "Item \(i)", year: 2020 + (i % 5), genres: ["#28"], posterName: "", rating: Double(i % 10), summary: "", posterURL: nil, durationMinutes: nil, mediaType: "movie", cast: nil, directors: nil, popularity: nil)
        }
        let vm = SearchViewModel(service: mock)
        vm.keyword = "Item"
        let clock = ContinuousClock()
        let start = clock.now
        await vm.search()
        let end = clock.now
        let elapsed = end - start
        #expect(!vm.results.isEmpty)
        #expect(elapsed < .seconds(2))
    }
}

