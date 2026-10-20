import SwiftUI

struct LibraryFilterControls: View {
    @Bindable var viewModel: LibraryViewModel

    var body: some View {
        Section("SORTING") {
            ForEach(LibrarySortOption.allCases) { option in
                Button {
                    viewModel.filterState.selectedSortOption = option
                    viewModel.filterState.saveToDefaults()
                } label: {
                    if viewModel.filterState.selectedSortOption == option {
                        Label(option.rawValue, systemImage: "checkmark")
                    } else {
                        Text(option.rawValue)
                    }
                }
            }
            Button {
                viewModel.filterState.sortAscending.toggle()
                viewModel.filterState.saveToDefaults()
            } label: {
                Label(
                    viewModel.filterState.sortAscending ? "Ascending" : "Descending",
                    systemImage: viewModel.filterState.sortAscending ? "arrow.up" : "arrow.down"
                )
            }
        }
        
        Section("FILTER") {
            Button { viewModel.toggleDownloadFilter() } label: {
                if viewModel.filterState.showDownloadedOnly {
                    Label("Show all books", systemImage: "books.vertical")
                } else {
                    Label("Downloaded only", systemImage: "arrow.down.circle")
                }
            }
            
            Button { viewModel.toggleSeriesOnlyFilter() } label: {
                if viewModel.filterState.showSeriesOnly {
                    Label("Show standalone books", systemImage: "books.vertical")
                } else {
                    Label("Series only", systemImage: "square.3.layers.3d.down.right")
                }
            }
        }
        
        Section("VIEW") {
            Button { viewModel.toggleSeriesMode() } label: {
                Label(
                    "Group series",
                    systemImage: viewModel.filterState.showSeriesGrouped
                        ? "square.stack.3d.up.fill"
                        : "square.stack.3d.up"
                )
            }
        }
        
        if viewModel.filterState.hasActiveFilters {
            Button(role: .destructive) {
                withAnimation(.spring(response: 0.3)) { viewModel.resetFilters() }
            } label: {
                Label("Reset all filters", systemImage: "arrow.counterclockwise")
            }
        }
    }
}
