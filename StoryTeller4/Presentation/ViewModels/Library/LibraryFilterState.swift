import SwiftUI

// MARK: - Enhanced Filter State mit Sortierrichtung
struct LibraryFilterState {
    var searchText: String = ""
    var selectedSortOption: LibrarySortOption = .title
    var sortAscending: Bool = true
    var showDownloadedOnly: Bool = false
    var showSeriesGrouped: Bool = false
    var showSeriesOnly: Bool = false
    
    var hasActiveFilters: Bool {
        showDownloadedOnly || showSeriesGrouped || showSeriesOnly || !searchText.isEmpty || !sortAscending
    }

    func matchesSearchFilter(_ book: Book) -> Bool {
        guard !searchText.isEmpty else { return true }
        
        return book.title.localizedCaseInsensitiveContains(searchText) ||
               (book.author?.localizedCaseInsensitiveContains(searchText) ?? false)
    }
    
    func matchesDownloadFilter(_ book: Book, isDownloaded: Bool) -> Bool {
        guard showDownloadedOnly else { return true }
        return isDownloaded
    }
    
    // FIX: Added the composite matching function required by LibraryViewModel
    func matches(book: Book, downloadManager: DownloadManager) -> Bool {
        // 1. Search Filter
        if !matchesSearchFilter(book) {
            return false
        }
        
        // 2. Download Filter
        if showDownloadedOnly {
            let isDownloaded = downloadManager.isBookDownloaded(book.id)
            if !matchesDownloadFilter(book, isDownloaded: isDownloaded) {
                return false
            }
        }
        
        // 3. Series Only Filter
        if showSeriesOnly {
            if let series = book.seriesSequence, !series.isEmpty {
                // Book belongs to at least one series
            } else {
                return false
            }
        }
        
        return true
    }
    
    func applySorting(to books: [Book]) -> [Book] {
        let sorted = books.sorted { book1, book2 in
            switch selectedSortOption {
            case .title:
                return book1.title.localizedCompare(book2.title) == .orderedAscending
            case .author:
                return (book1.author ?? "Unbekannt").localizedCompare(book2.author ?? "Unbekannt") == .orderedAscending
            case .recent:
                return book1.id > book2.id
            }
        }
        return sortAscending ? sorted : sorted.reversed()
    }
    
    mutating func loadFromDefaults() {
        showDownloadedOnly = UserDefaults.standard.bool(forKey: "library_show_downloaded_only")
        showSeriesGrouped = UserDefaults.standard.bool(forKey: "library_show_series_grouped")
        showSeriesOnly = UserDefaults.standard.bool(forKey: "library_show_series_only")
        sortAscending = UserDefaults.standard.bool(forKey: "library_sort_ascending")
        if let sortRaw = UserDefaults.standard.string(forKey: "library_sort_option"),
           let sortOption = LibrarySortOption(rawValue: sortRaw) {
            selectedSortOption = sortOption
        }
    }
    
    func saveToDefaults() {
        UserDefaults.standard.set(showDownloadedOnly, forKey: "library_show_downloaded_only")
        UserDefaults.standard.set(showSeriesGrouped, forKey: "library_show_series_grouped")
        UserDefaults.standard.set(showSeriesOnly, forKey: "library_show_series_only")
        UserDefaults.standard.set(sortAscending, forKey: "library_sort_ascending")
        UserDefaults.standard.set(selectedSortOption.rawValue, forKey: "library_sort_option")
    }
    
    mutating func reset() {
        searchText = ""
        showDownloadedOnly = false
        showSeriesGrouped = false
        showSeriesOnly = false
        sortAscending = true
        selectedSortOption = .title
        saveToDefaults()
    }
}
