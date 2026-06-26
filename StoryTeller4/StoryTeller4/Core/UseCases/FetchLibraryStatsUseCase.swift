//
//  FetchLibraryStatsUseCaseProtocol.swift
//  StoryTeller4
//
//  Created by Boris Eder on 25.06.26.
//


import Foundation

// MARK: - Protocol (Domain Layer)
protocol FetchLibraryStatsUseCaseProtocol: Sendable {
    func execute(libraryId: String) async throws -> Int
}

// MARK: - Implementation (Domain Layer)
// Hält nur ein Repository-Protocol – kein Wissen über AudiobookshelfClient
final class FetchLibraryStatsUseCase: FetchLibraryStatsUseCaseProtocol {
    private let libraryStatsRepository: LibraryStatsRepositoryProtocol

    init(libraryStatsRepository: LibraryStatsRepositoryProtocol) {
        self.libraryStatsRepository = libraryStatsRepository
    }

    func execute(libraryId: String) async throws -> Int {
        return try await libraryStatsRepository.fetchTotalBooks(libraryId: libraryId)
    }
}