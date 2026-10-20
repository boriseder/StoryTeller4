//
//  APIEndpoint.swift
//  StoryTeller4
//
//  Created by Boris Eder on 11.12.25.
//


import Foundation

enum APIEndpoint {
    case cover(bookId: String)
    case authorImage(authorId: String)
    
    func path() -> String {
        switch self {
        case .cover(let bookId):
            return "/api/items/\(bookId)/cover"
        case .authorImage(let authorId):
            return "/api/authors/\(authorId)/image"
        }
    }
    
    func url(baseURL: String) -> URL? {
        // Ensure baseURL doesn't have trailing slash and path starts with one
        let cleanBase = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(cleanBase)\(path())")
    }
}