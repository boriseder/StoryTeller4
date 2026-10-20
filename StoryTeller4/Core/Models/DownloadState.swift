//
//  DownloadState.swift
//  StoryTeller4
//
//  Created by Boris Eder on 23.06.26.
//


import Foundation

// MARK: - DownloadState
//
// Plain value type that the repository emits upward to DownloadManager.
// Replaces the old pattern of the repository writing directly into
// DownloadManager's dictionaries. Nothing below the Manager layer
// imports or knows about this type's consumer.

struct DownloadState: Sendable {
    var progress: Double        = 0.0
    var stage: DownloadStage    = .preparing
    var statusMessage: String   = ""
    var isDownloading: Bool     = false
}

// MARK: - Callback Typealias
//
// Replaces DownloadProgressCallback (bookId, Double, String, DownloadStage).
// The repository fires this once per meaningful state change.

typealias DownloadStateCallback = @Sendable (String, DownloadState) -> Void