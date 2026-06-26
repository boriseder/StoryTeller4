//
//  LibraryStatsRepositoryProtocol.swift
//  StoryTeller4
//
//  Created by Boris Eder on 25.06.26.
//


import Foundation

// MARK: - Protocol (Domain Layer)
// Nur in der Domain bekannt – kein AudiobookshelfClient sichtbar
protocol LibraryStatsRepositoryProtocol: Sendable {
    func fetchTotalBooks(libraryId: String) async throws -> Int
}

// MARK: - Implementation (Data Layer)
final class LibraryStatsRepository: LibraryStatsRepositoryProtocol {
    private let api: AudiobookshelfClient

    init(api: AudiobookshelfClient) {
        self.api = api
    }

    func fetchTotalBooks(libraryId: String) async throws -> Int {
        return try await api.libraries.fetchLibraryStats(libraryId: libraryId)
    }
}

// MARK: - Placeholder
extension LibraryStatsRepository {
    static var placeholder: LibraryStatsRepository {
        LibraryStatsRepository(api: AudiobookshelfClient(baseURL: "", authToken: ""))
    }
}