import Foundation

struct DownloadProgressState {
    var bookToDelete: Book?
    var showingDeleteConfirmation: Bool = false
    var showingDeleteAllConfirmation: Bool = false
    var totalStorageUsed: Int64 = 0
    var availableStorage: Int64 = 0
    var showStorageWarning: Bool = false
    
    let storageThreshold: Int64 = 500_000_000
    
    mutating func updateStorage(totalUsed: Int64, available: Int64, warningLevel: StorageWarningLevel) {
        totalStorageUsed = totalUsed
        availableStorage = available
        showStorageWarning = warningLevel != .none
    }
    
    mutating func requestDelete(_ book: Book) {
        bookToDelete = book
        showingDeleteConfirmation = true
    }
    
    mutating func cancelDelete() {
        bookToDelete = nil
        showingDeleteConfirmation = false
    }
    
    mutating func confirmDelete() {
        bookToDelete = nil
        showingDeleteConfirmation = false
    }
    
    mutating func requestDeleteAll() {
        showingDeleteAllConfirmation = true
    }
    
    mutating func cancelDeleteAll() {
        showingDeleteAllConfirmation = false
    }
    
    mutating func confirmDeleteAll() {
        showingDeleteAllConfirmation = false
    }
}
