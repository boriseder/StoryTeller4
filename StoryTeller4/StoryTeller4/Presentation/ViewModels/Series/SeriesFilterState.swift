import Foundation

struct SeriesFilterState {
    var searchText: String = ""
    var selectedSortOption: SeriesSortOption = .name
    
    func matchesSearchFilter(_ series: Series) -> Bool {
        guard !searchText.isEmpty else { return true }
        
        return series.name.localizedCaseInsensitiveContains(searchText) ||
               (series.author?.localizedCaseInsensitiveContains(searchText) ?? false)
    }
    
    func applySorting(to series: [Series]) -> [Series] {
        return series.sorted { series1, series2 in
            switch selectedSortOption {
            case .name:
                return series1.name.localizedCompare(series2.name) == .orderedAscending
            case .recent:
                return series1.addedAt > series2.addedAt
            case .bookCount:
                return series1.bookCount > series2.bookCount
            case .duration:
                return series1.totalDuration > series2.totalDuration
            }
        }
    }
}
