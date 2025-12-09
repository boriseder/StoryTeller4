//
//  UserData.swift
//  StoryTeller3
//
//  Created by Boris Eder on 28.11.25.
//
import Foundation

// MARK: - User Model Extension
struct UserData: Codable {
    let id: String
    let username: String
    let email: String?
    let type: String
    let token: String
    let mediaProgress: [MediaProgress]
    let bookmarks: [Bookmark]
    
    // Helpers
    func bookmarks(for libraryItemId: String) -> [Bookmark] {
        bookmarks.filter { $0.libraryItemId == libraryItemId }
            .sorted { $0.time < $1.time }
    }
    
    func progress(for libraryItemId: String) -> MediaProgress? {
        mediaProgress.first { $0.libraryItemId == libraryItemId }
    }
}
